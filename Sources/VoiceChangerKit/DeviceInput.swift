import CoreAudio
import Foundation

/// Captures straight from one device's IOProc. AVAudioEngine's input node goes through a system-made
/// aggregate of the default devices, which resets repeatedly while a Bluetooth headset switches mode.
final class DeviceInput {
    enum Failure: LocalizedError {
        case unsupportedFormat
        case hal(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "The selected microphone has no usable input channels."
            case .hal(let step, let status): "Could not \(step) the microphone (error \(status))."
            }
        }
    }

    typealias Handler = (UnsafePointer<AudioBufferList>, UInt32) -> Void

    let device: AudioDeviceID
    let sampleRate: Double
    /// Called on an arbitrary thread when the device changed format and capture has to be rebuilt.
    var onInvalidated: (() -> Void)?

    private let queue = DispatchQueue(label: "local.voicechanger.input-listener")
    private var procID: AudioDeviceIOProcID?
    private var started = false
    private var invalidated = false
    private var listener: AudioObjectPropertyListenerBlock?
    private let stateLock = NSLock()

    private static let watched: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
        (kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput),
        (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
    ]

    init(device: AudioDeviceID, handler: @escaping Handler) throws {
        self.device = device

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = Self.address(kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeInput)
        let isFloat = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr,
            format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & isFloat == isFloat,
            format.mBitsPerChannel == 32, format.mChannelsPerFrame > 0, format.mSampleRate > 0
        else { throw Failure.unsupportedFormat }
        sampleRate = format.mSampleRate

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil) { _, input, _, output, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            if let first = buffers.first, first.mNumberChannels > 0, first.mData != nil {
                handler(input, first.mDataByteSize / (4 * first.mNumberChannels))
            }
            // Devices with outputs hand those buffers to this callback too; leave them silent.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
        guard status == noErr, procID != nil else { throw Failure.hal("open", status) }
    }

    deinit { stop() }

    var isRunning: Bool { stateLock.withLock { started && !invalidated } }

    func start() throws {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let notify = self.stateLock.withLock {
                let first = !self.invalidated
                self.invalidated = true
                return first
            }
            if notify { self.onInvalidated?() }
        }
        listener = block
        for (selector, scope) in Self.watched {
            var address = Self.address(selector, scope)
            AudioObjectAddPropertyListenerBlock(device, &address, queue, block)
        }
        let status = AudioDeviceStart(device, procID)
        guard status == noErr else { throw Failure.hal("start", status) }
        stateLock.withLock { started = true }
    }

    func stop() {
        if let listener {
            for (selector, scope) in Self.watched {
                var address = Self.address(selector, scope)
                AudioObjectRemovePropertyListenerBlock(device, &address, queue, listener)
            }
        }
        listener = nil
        if let procID {
            AudioDeviceStop(device, procID)
            AudioDeviceDestroyIOProcID(device, procID)
        }
        procID = nil
        stateLock.withLock { started = false }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
