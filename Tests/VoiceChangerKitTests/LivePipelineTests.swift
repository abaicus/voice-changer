import Foundation
import Testing

@testable import VoiceChangerKit

/// Opens real devices, so it only runs on request: `VC_LIVE=1 swift test --filter live`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VC_LIVE"] == "1"))
func livePipelineRunsOnDefaultMicWithoutUnderruns() async throws {
    let devices = AudioDevices.all()
    let virtualMic = devices.first { $0.outputChannels > 0 && $0.name.contains("BlackHole") }
    let defaultInput = try #require(AudioDevices.defaultInputID())
    let input = try #require(devices.first { $0.id == defaultInput && $0.id != virtualMic?.id })

    let pipeline = AudioPipeline()
    var params = VoiceParameters()
    params.pitch = 5
    try pipeline.start(input: input.id, virtualMic: virtualMic?.id, params: params, bypass: false)
    if let output = AudioDevices.defaultOutputID(), output != virtualMic?.id {
        pipeline.setMonitorVolume(0)
        try pipeline.setMonitor(device: output)
    }
    try await Task.sleep(for: .seconds(1))
    let settled = pipeline.underruns
    _ = pipeline.readLevels()
    try await Task.sleep(for: .seconds(4))
    let levels = pipeline.readLevels()
    let underruns = pipeline.underruns
    print("LIVE input=\(input.name) rate=\(pipeline.sampleRate) virtualMic=\(virtualMic?.name ?? "none") levels=\(levels) underruns=\(settled)->\(underruns)")
    pipeline.stop()

    #expect(underruns.virtualMic == settled.virtualMic)
    #expect(underruns.monitor == settled.monitor)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["VC_LIVE"] == "1"))
func liveStartOnUnknownDeviceThrowsAndLeavesPipelineStopped() {
    let pipeline = AudioPipeline()
    #expect(throws: (any Error).self) {
        try pipeline.start(input: 0x7FFF_FFF0, virtualMic: nil, params: VoiceParameters(), bypass: false)
    }
    #expect(!pipeline.captureIsRunning)
}
