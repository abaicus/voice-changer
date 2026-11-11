import Foundation
import Testing

@testable import VoiceChangerKit

private func temporaryStore() -> PresetStore {
    PresetStore(url: FileManager.default.temporaryDirectory.appending(path: "vc-tests-\(UUID().uuidString)/presets.json"))
}

@Test func presetsSurviveASaveAndLoad() throws {
    let store = temporaryStore()
    var params = VoiceParameters()
    params.pitch = 3.5
    params.reverbMix = 0.4
    let presets = [Preset(name: "Mine", params: params)]
    try store.save(presets)
    #expect(store.load() == presets)
}

@Test func presetsFromOlderVersionsLoadWithDefaultsForNewParameters() throws {
    let store = temporaryStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"[{"id":"abc","name":"Old","params":{"pitch":-2}}]"#.utf8).write(to: store.url)
    let loaded = store.load()
    #expect(loaded.first?.params.pitch == -2)
    #expect(loaded.first?.params.highCut == VoiceParameters().highCut)
}

@Test func unreadableFileIsSetAsideRatherThanOverwritten() throws {
    let store = temporaryStore()
    let directory = store.url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: store.url)
    #expect(store.load().isEmpty)
    try store.save([])
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
}

@Test func builtInPresetsHaveUniqueStableIDs() {
    #expect(Set(Preset.builtIns.map(\.id)).count == Preset.builtIns.count)
    #expect(Preset.builtIns.allSatisfy { $0.isBuiltIn })
    #expect(!Preset(name: "Custom", params: VoiceParameters()).isBuiltIn)
}

@Test func builtInPresetsHaveDistinctSymbols() {
    #expect(Set(Preset.builtIns.map { $0.symbolName }).count == Preset.builtIns.count)
    #expect(Preset.builtIns.allSatisfy { $0.symbolName != "slider.horizontal.3" })
    #expect(Preset.builtIns[0].symbolName == "person.wave.2.fill")
    let symbols = Preset.builtIns.map { $0.symbolName }
    #expect(symbols == ["person.wave.2.fill", "arrow.down.circle.fill", "arrow.up.circle.fill", "hare.fill", "flame.fill", "cpu.fill", "phone.fill", "mountain.2.fill"])
}

@Test func customPresetUsesSliderSymbol() {
    #expect(Preset(name: "Mine", params: VoiceParameters()).symbolName == "slider.horizontal.3")
}
