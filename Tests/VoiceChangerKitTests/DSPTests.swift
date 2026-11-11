import CoreAudio
import Foundation
import Testing
import VoiceDSP

@testable import VoiceChangerKit

private let sampleRate = 48000.0

private func sine(_ hz: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / sampleRate)) }
}

private func capture(_ engine: OpaquePointer, _ samples: inout [Float], offset: Int, frames: Int) {
    samples.withUnsafeMutableBufferPointer { buffer in
        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: buffer.baseAddress! + offset))
        vc_capture(engine, &list, UInt32(frames))
    }
}

private func render(_ engine: OpaquePointer, output: Int32 = VC_OUTPUT_VIRTUAL_MIC, frames: Int) -> [Float] {
    var out = [Float](repeating: 0, count: frames)
    out.withUnsafeMutableBufferPointer { buffer in
        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: buffer.baseAddress))
        vc_render(engine, output, &list, UInt32(frames))
    }
    return out
}

/// Runs `input` through capture → render with a reader clock `readerRatio` times the writer's.
private func run(_ input: [Float], params: VoiceParameters, readerRatio: Double = 1) -> (output: [Float], underruns: UInt32) {
    let engine = vc_create(sampleRate)!
    defer { vc_destroy(engine) }
    var raw = params.dspParams(bypass: false)
    vc_set_params(engine, &raw)

    var input = input
    var output: [Float] = []
    var owed = 0.0
    let writeBlock = 512, readBlock = 480
    for offset in stride(from: 0, to: input.count - writeBlock, by: writeBlock) {
        capture(engine, &input, offset: offset, frames: writeBlock)
        owed += Double(writeBlock) * readerRatio
        while owed >= Double(readBlock) {
            output += render(engine, frames: readBlock)
            owed -= Double(readBlock)
        }
    }
    return (output, vc_underruns(engine, VC_OUTPUT_VIRTUAL_MIC))
}

private func frequency(of samples: ArraySlice<Float>) -> Double {
    var crossings = 0
    var previous: Float = 0
    for sample in samples {
        if previous <= 0, sample > 0 { crossings += 1 }
        previous = sample
    }
    return Double(crossings) * sampleRate / Double(samples.count)
}

private func peak(_ samples: ArraySlice<Float>) -> Float { samples.reduce(0) { max($0, abs($1)) } }

@Test func defaultParametersPassAudioThroughUnchanged() {
    let (output, underruns) = run(sine(220, seconds: 2), params: VoiceParameters())
    let tail = output.suffix(48000)
    #expect(underruns == 0)
    #expect(abs(frequency(of: tail) - 220) < 2)
    #expect(abs(peak(tail) - 0.5) < 0.01)
}

@Test func pitchShiftsByTheRequestedInterval() {
    var params = VoiceParameters()
    params.pitch = 12
    let (output, _) = run(sine(200, seconds: 2), params: params)
    #expect(abs(frequency(of: output.suffix(48000)) - 400) < 12)

    params.pitch = -12
    let (lower, _) = run(sine(400, seconds: 2), params: params)
    #expect(abs(frequency(of: lower.suffix(48000)) - 200) < 6)
}

@Test(arguments: [1.0005, 0.9995])
func clockDriftBetweenDevicesNeverUnderruns(readerRatio: Double) {
    let (output, underruns) = run(sine(220, seconds: 60), params: VoiceParameters(), readerRatio: readerRatio)
    #expect(underruns == 0)
    #expect(peak(output.suffix(48000)) > 0.45)
    // A dropped or repeated chunk would show up as a jump far larger than a 220 Hz sine can make.
    let tail = Array(output.suffix(48000 * 30))
    let largestStep = zip(tail, tail.dropFirst()).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
    #expect(largestStep < 0.02)
}

@Test func micOnOneChannelOfStereoInterfaceKeepsFullLevel() {
    let engine = vc_create(sampleRate)!
    defer { vc_destroy(engine) }
    var raw = VoiceParameters().dspParams(bypass: true)
    vc_set_params(engine, &raw)

    let mono = sine(220, seconds: 1)
    var interleaved: [Float] = mono.flatMap { [$0, 0] }
    var output: [Float] = []
    for offset in stride(from: 0, to: mono.count - 512, by: 512) {
        interleaved.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 512 * 8, mData: buffer.baseAddress! + offset * 2))
            vc_capture(engine, &list, 512)
        }
        output += render(engine, frames: 512)
    }
    let level = peak(output.suffix(4800))
    #expect(abs(level - 0.5) < 0.01, "peak \(level), underruns \(vc_underruns(engine, VC_OUTPUT_VIRTUAL_MIC))")
}

@Test func gateSilencesSignalBelowThreshold() {
    var params = VoiceParameters()
    params.gateThreshold = -30
    let quiet = run(sine(220, seconds: 1, amplitude: 0.003), params: params).output
    let loud = run(sine(220, seconds: 1, amplitude: 0.3), params: params).output
    #expect(peak(quiet.suffix(4800)) < 0.0003)
    #expect(peak(loud.suffix(4800)) > 0.28)
}

@Test func everyBuiltInPresetProducesBoundedAudibleOutput() {
    for preset in Preset.builtIns {
        let output = run(sine(180, seconds: 1.5), params: preset.params).output
        let level = peak(output.suffix(24000))
        #expect(level > 0.05 && level <= 1.0, "\(preset.name) peaked at \(level)")
        #expect(output.allSatisfy { $0.isFinite }, "\(preset.name) produced non-finite samples")
    }
}
