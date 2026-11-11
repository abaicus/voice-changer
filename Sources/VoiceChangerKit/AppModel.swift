import AVFoundation
import Observation

@MainActor @Observable
public final class AppModel {
    /// Device fields hold a device UID; an empty string means "system default" (or "none" for the virtual mic).
    public struct Settings: Codable, Equatable {
        public var enabled = false
        public var inputUID = ""
        public var virtualMicUID = ""
        public var monitorUID = ""
        public var monitorEnabled = false
        public var monitorVolume: Float = 1
        public var bypass = false
        public var selectedPresetID = Preset.builtIns[0].id
        public var params = VoiceParameters()
    }

    public var settings: Settings {
        didSet { settingsChanged(from: oldValue) }
    }

    public private(set) var devices: [AudioDevice] = []
    public private(set) var customPresets: [Preset]
    public private(set) var isRunning = false
    public private(set) var isStarting = false
    public private(set) var status = ""
    public private(set) var activeInputName = ""
    public private(set) var inputLevel: Float = 0
    public private(set) var outputLevel: Float = 0

    private let pipeline = AudioPipeline()
    private let presetStore: PresetStore
    private let defaults: UserDefaults
    private var rerouteTask: Task<Void, Never>?
    /// Engine setup can block for seconds while a Bluetooth device switches mode, so it never runs on the main thread.
    private let audioQueue = DispatchQueue(label: "local.voicechanger.audio", qos: .userInitiated)
    private var routeGeneration = 0
    private var meterTimer: Timer?
    private static let settingsKey = "settings"

    public init(presetStore: PresetStore = PresetStore(), defaults: UserDefaults = .standard) {
        self.presetStore = presetStore
        self.defaults = defaults
        customPresets = presetStore.load()
        devices = AudioDevices.all()

        if let data = defaults.data(forKey: Self.settingsKey),
            let saved = try? JSONDecoder().decode(Settings.self, from: data)
        {
            settings = saved
        } else {
            settings = Settings()
            settings.virtualMicUID = devices.first { $0.outputChannels > 0 && $0.name.contains("BlackHole") }?.uid ?? ""
        }

        AudioDevices.onChange { [weak self] in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        pipeline.onEngineStopped = { [weak self] in
            DispatchQueue.main.async { self?.scheduleReroute() }
        }
        if settings.enabled { requestAccessAndRoute() }
    }

    // MARK: Devices

    public var virtualMicDevice: AudioDevice? {
        devices.first { $0.uid == settings.virtualMicUID && $0.outputChannels > 0 }
    }

    public var outputDevices: [AudioDevice] { devices.filter { $0.outputChannels > 0 } }

    /// The virtual mic is excluded from both lists: capturing or monitoring it would feed the output back in.
    public var inputDevices: [AudioDevice] {
        devices.filter { $0.inputChannels > 0 && $0.id != virtualMicDevice?.id }
    }

    public var monitorDevices: [AudioDevice] {
        outputDevices.filter { $0.id != virtualMicDevice?.id }
    }

    // MARK: Presets

    public var allPresets: [Preset] { Preset.builtIns + customPresets }

    public var selectedPreset: Preset? { allPresets.first { $0.id == settings.selectedPresetID } }

    public var isModified: Bool { selectedPreset?.params != settings.params }

    public func select(_ preset: Preset) {
        settings.selectedPresetID = preset.id
        settings.params = preset.params
    }

    public func revertToPreset() {
        if let selectedPreset { settings.params = selectedPreset.params }
    }

    public func saveAsNewPreset(named name: String) {
        let preset = Preset(name: name, params: settings.params)
        customPresets.append(preset)
        settings.selectedPresetID = preset.id
        persistPresets()
    }

    public func updateSelectedPreset() {
        guard let index = customPresets.firstIndex(where: { $0.id == settings.selectedPresetID }) else { return }
        customPresets[index].params = settings.params
        persistPresets()
    }

    public func renamePreset(id: String, to name: String) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].name = name
        persistPresets()
    }

    public func deletePreset(id: String) {
        customPresets.removeAll { $0.id == id }
        persistPresets()
        if settings.selectedPresetID == id { select(Preset.builtIns[0]) }
    }

    private func persistPresets() {
        do {
            try presetStore.save(customPresets)
        } catch {
            status = "Could not save presets: \(error.localizedDescription)"
        }
    }

    // MARK: Routing

    private func settingsChanged(from old: Settings) {
        guard settings != old else { return }
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }

        if settings.params != old.params || settings.bypass != old.bypass {
            pipeline.setParams(settings.params, bypass: settings.bypass)
        }
        if settings.monitorVolume != old.monitorVolume {
            pipeline.setMonitorVolume(settings.monitorVolume)
        }
        if settings.enabled != old.enabled {
            if settings.enabled { requestAccessAndRoute() } else { shutDown() }
        } else if settings.enabled,
            settings.inputUID != old.inputUID || settings.virtualMicUID != old.virtualMicUID
                || settings.monitorUID != old.monitorUID || settings.monitorEnabled != old.monitorEnabled
        {
            route()
        }
    }

    private var startAttempts = 0
    private var monitorAttempts = 0
    private var automaticRestarts: [Date] = []
    private static let maxStartAttempts = 4
    private static let settlingStatus = "Waiting for the audio device to settle…"

    private struct RouteOutcome {
        var restarted = false
        var monitorError: String?
    }

    private func devicesChanged() {
        devices = AudioDevices.all()
        scheduleReroute()
    }

    /// Device changes arrive in bursts (unplugging fires several notifications), so coalesce them.
    private func scheduleReroute(delay: Duration = .milliseconds(250)) {
        guard settings.enabled else { return }
        rerouteTask?.cancel()
        rerouteTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.route(automatic: true)
        }
    }

    private func requestAccessAndRoute() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                fail("Microphone access is denied. Allow it in System Settings › Privacy & Security › Microphone.")
                return
            }
            if settings.enabled { route() }
        }
    }

    private func route(automatic: Bool = false) {
        guard settings.enabled else { return }
        rerouteTask?.cancel()
        devices = AudioDevices.all()
        let virtualMic = virtualMicDevice?.id
        let inputs = inputDevices
        let defaultInput = AudioDevices.defaultInputID()
        guard
            let input = inputs.first(where: { $0.uid == settings.inputUID })
                ?? inputs.first(where: { $0.id == defaultInput }) ?? inputs.first
        else {
            retryOrFail("No microphone found.")
            return
        }

        var monitor: AudioDeviceID?
        var monitorWarning: String?
        if settings.monitorEnabled {
            let candidates = monitorDevices
            let defaultOutput = AudioDevices.defaultOutputID()
            monitor = (candidates.first { $0.uid == settings.monitorUID } ?? candidates.first { $0.id == defaultOutput })?.id
            if monitor == nil {
                monitorWarning = "Monitoring is off: no output device available besides the virtual mic."
            }
        }

        routeGeneration += 1
        let generation = routeGeneration
        let params = settings.params
        let bypass = settings.bypass
        let volume = settings.monitorVolume
        if !isRunning { isStarting = true }

        audioQueue.async { [weak self, pipeline] in
            let result = Result<RouteOutcome, Error> {
                var outcome = RouteOutcome()
                // Only what actually stopped or changed is rebuilt: restarting the microphone makes Bluetooth headsets switch mode, which stops the other engines again.
                if !pipeline.captureIsRunning || pipeline.input != input.id || pipeline.virtualMic != virtualMic {
                    try pipeline.start(input: input.id, virtualMic: virtualMic, params: params, bypass: bypass)
                    pipeline.setMonitorVolume(volume)
                    outcome.restarted = true
                } else if !pipeline.virtualMicIsRunning {
                    try pipeline.restartVirtualMic()
                }
                if pipeline.monitor != monitor || !pipeline.monitorIsRunning {
                    do {
                        try pipeline.setMonitor(device: monitor)
                    } catch {
                        outcome.monitorError = error.localizedDescription
                    }
                }
                return outcome
            }
            DispatchQueue.main.async {
                self?.finishRoute(
                    generation: generation, inputName: input.name, automatic: automatic,
                    monitorWarning: monitorWarning, result: result)
            }
        }
    }

    private func finishRoute(
        generation: Int, inputName: String, automatic: Bool, monitorWarning: String?,
        result: Result<RouteOutcome, Error>
    ) {
        guard generation == routeGeneration, settings.enabled else { return }
        isStarting = false
        let outcome: RouteOutcome
        switch result {
        case .success(let value): outcome = value
        case .failure(let error):
            retryOrFail("Could not start audio: \(error.localizedDescription)")
            return
        }

        // The sliders may have moved while the engines were being built.
        pipeline.setParams(settings.params, bypass: settings.bypass)
        pipeline.setMonitorVolume(settings.monitorVolume)
        activeInputName = inputName
        isRunning = true
        startAttempts = 0
        status = monitorWarning ?? ""
        startMetering()

        if let monitorError = outcome.monitorError {
            monitorAttempts += 1
            if monitorAttempts < Self.maxStartAttempts {
                scheduleReroute(delay: .milliseconds(700))
            } else {
                status = "Could not start monitoring: \(monitorError)"
            }
        } else {
            monitorAttempts = 0
        }

        if outcome.restarted, automatic {
            let now = Date()
            automaticRestarts = automaticRestarts.filter { now.timeIntervalSince($0) < 20 } + [now]
            if automaticRestarts.count > 4 {
                fail("The audio device keeps resetting, so the voice changer was switched off. Try a different microphone or monitor output.")
            }
        }
    }

    private func retryOrFail(_ message: String) {
        startAttempts += 1
        guard startAttempts < Self.maxStartAttempts else {
            fail(message)
            return
        }
        isRunning = false
        status = Self.settlingStatus
        scheduleReroute(delay: .milliseconds(700))
    }

    private func fail(_ message: String) {
        shutDown()
        status = message
        settings.enabled = false
    }

    private func shutDown() {
        startAttempts = 0
        monitorAttempts = 0
        automaticRestarts = []
        if status == Self.settlingStatus { status = "" }
        rerouteTask?.cancel()
        meterTimer?.invalidate()
        meterTimer = nil
        routeGeneration += 1
        audioQueue.async { [pipeline] in pipeline.stop() }
        isRunning = false
        isStarting = false
        inputLevel = 0
        outputLevel = 0
    }

    private func startMetering() {
        guard meterTimer == nil else { return }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let levels = self.pipeline.readLevels()
                self.inputLevel = max(levels.input, self.inputLevel * 0.92)
                self.outputLevel = max(levels.output, self.outputLevel * 0.92)
            }
        }
    }
}
