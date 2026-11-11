import AVFoundation
import ObjCSupport
import VoiceDSP

/// Mic → DSP → virtual mic (+ optional monitor). Each device gets its own engine so
/// they can run at different sample rates and on different clocks; the DSP core
/// bridges them with drift-compensating ring buffers.
public final class AudioPipeline: @unchecked Sendable {
    public enum Failure: LocalizedError {
        case noInputChannels
        case engine(String)

        public var errorDescription: String? {
            switch self {
            case .noInputChannels: "The audio device has no usable format."
            case .engine(let reason): "The audio engine rejected the device setup: \(reason)"
            }
        }
    }

    public private(set) var input: AudioDeviceID?
    public private(set) var virtualMic: AudioDeviceID?
    public private(set) var monitor: AudioDeviceID?
    public private(set) var sampleRate: Double = 0

    /// Called on an arbitrary thread when macOS stopped an engine (device unplugged, format changed).
    public var onEngineStopped: (() -> Void)?

    /// Engine setup runs on one background queue while the UI reads levels and pushes parameters, so the DSP handle is swapped under this lock.
    private let dspLock = NSLock()
    private var dsp: OpaquePointer?
    private var capture: DeviceInput?
    private var virtualMicEngine: AVAudioEngine?
    private var monitorEngine: AVAudioEngine?
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    public init() {}

    deinit { stop() }

    public var captureIsRunning: Bool { capture?.isRunning ?? false }

    public var virtualMicIsRunning: Bool { virtualMic == nil || virtualMicEngine?.isRunning == true }

    public var monitorIsRunning: Bool { monitor == nil || monitorEngine?.isRunning == true }

    public func start(input: AudioDeviceID, virtualMic: AudioDeviceID?, params: VoiceParameters, bypass: Bool) throws {
        stop()
        AudioDevices.requestSmallBuffer(input)

        var dsp: OpaquePointer?
        let capture = try DeviceInput(device: input) { buffers, frames in
            if let dsp { vc_capture(dsp, buffers, frames) }
        }
        capture.onInvalidated = { [weak self] in self?.onEngineStopped?() }
        dsp = vc_create(capture.sampleRate)
        dspLock.withLock { self.dsp = dsp }
        sampleRate = capture.sampleRate
        setParams(params, bypass: bypass)

        do {
            if let virtualMic {
                self.virtualMic = virtualMic
                virtualMicEngine = try makeOutput(device: virtualMic, output: VC_OUTPUT_VIRTUAL_MIC)
            }
            try capture.start()
        } catch {
            capture.stop()
            stop()
            throw error
        }
        self.capture = capture
        self.input = input
    }

    /// Rebuilds only the virtual mic output after macOS stopped it, leaving the microphone running.
    public func restartVirtualMic() throws {
        guard let virtualMic else { return }
        if let virtualMicEngine {
            unobserve(virtualMicEngine)
            _ = VCCatchException { virtualMicEngine.stop() }
        }
        virtualMicEngine = nil
        virtualMicEngine = try makeOutput(device: virtualMic, output: VC_OUTPUT_VIRTUAL_MIC)
    }

    public func setMonitor(device: AudioDeviceID?) throws {
        if let monitorEngine {
            unobserve(monitorEngine)
            _ = VCCatchException { monitorEngine.stop() }
        }
        monitorEngine = nil
        monitor = nil
        guard let device, dsp != nil else { return }
        monitorEngine = try makeOutput(device: device, output: VC_OUTPUT_MONITOR)
        monitor = device
    }

    public func stop() {
        capture?.stop()
        capture = nil
        for engine in [monitorEngine, virtualMicEngine].compactMap({ $0 }) {
            unobserve(engine)
            _ = VCCatchException { engine.stop() }
        }
        monitorEngine = nil
        virtualMicEngine = nil
        input = nil
        virtualMic = nil
        monitor = nil
        let old = dspLock.withLock {
            let old = dsp
            dsp = nil
            return old
        }
        // Capture and engines are stopped, so no audio callback can still be using the DSP.
        if let old { vc_destroy(old) }
    }

    public func setParams(_ params: VoiceParameters, bypass: Bool) {
        var raw = params.dspParams(bypass: bypass)
        dspLock.withLock {
            if let dsp { vc_set_params(dsp, &raw) }
        }
    }

    public func setMonitorVolume(_ volume: Float) {
        dspLock.withLock {
            if let dsp { vc_set_monitor_volume(dsp, volume) }
        }
    }

    /// Linear peaks since the previous call.
    public func readLevels() -> (input: Float, output: Float) {
        var input: Float = 0, output: Float = 0
        dspLock.withLock {
            if let dsp { vc_read_levels(dsp, &input, &output) }
        }
        return (input, output)
    }

    public var underruns: (virtualMic: UInt32, monitor: UInt32) {
        dspLock.withLock {
            guard let dsp else { return (0, 0) }
            return (vc_underruns(dsp, VC_OUTPUT_VIRTUAL_MIC), vc_underruns(dsp, VC_OUTPUT_MONITOR))
        }
    }

    private func makeOutput(device: AudioDeviceID, output: Int32) throws -> AVAudioEngine {
        guard let dsp, let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw Failure.noInputChannels
        }
        AudioDevices.requestSmallBuffer(device)
        let engine = AVAudioEngine()
        do {
            try guarded {
                let source = AVAudioSourceNode(format: format) { _, _, frames, buffers in
                    vc_render(dsp, output, buffers, frames)
                    return noErr
                }
                try engine.outputNode.auAudioUnit.setDeviceID(device)
                engine.attach(source)
                engine.connect(source, to: engine.mainMixerNode, format: format)
                try engine.start()
            }
        } catch {
            _ = VCCatchException { engine.stop() }
            throw error
        }
        observe(engine)
        return engine
    }

    /// AVAudioEngine reports some failures as Objective-C exceptions, which Swift cannot catch and which corrupt the process if they unwind further.
    private func guarded(_ body: () throws -> Void) throws {
        var thrown: Error?
        let reason = VCCatchException {
            do { try body() } catch { thrown = error }
        }
        if let reason { throw Failure.engine(reason) }
        if let thrown { throw thrown }
    }

    private func observe(_ engine: AVAudioEngine) {
        observers[ObjectIdentifier(engine)] = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.onEngineStopped?()
        }
    }

    private func unobserve(_ engine: AVAudioEngine) {
        if let observer = observers.removeValue(forKey: ObjectIdentifier(engine)) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
