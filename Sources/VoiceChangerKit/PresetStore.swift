import Foundation

public struct PresetStore {
    public let url: URL

    public init(url: URL = PresetStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "VoiceChanger/presets.json")
    }

    public func load() -> [Preset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let presets = try? JSONDecoder().decode([Preset].self, from: data) { return presets }
        // Keep the unreadable file around instead of letting the next save overwrite it.
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))"))
        return []
    }

    public func save(_ presets: [Preset]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: url, options: .atomic)
    }
}
