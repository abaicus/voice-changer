import Foundation

enum AppInfo {
    static let repo = URL(string: "https://github.com/abaicus/voice-changer")!
    static let website = URL(string: "https://abaic.us/voice-changer")!
    static let license = URL(string: "https://github.com/abaicus/voice-changer/blob/master/LICENSE")!
    static let blackHole = URL(string: "https://github.com/ExistentialAudio/BlackHole")!
    static let signalsmith = URL(string: "https://github.com/Signalsmith-Audio/signalsmith-stretch")!

    static let aboutWindowID = "about"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var versionLabel: String { version == "dev" ? version : "v\(version)" }
}
