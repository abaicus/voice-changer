// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceChanger",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VoiceDSP",
            exclude: [
                "vendor/signalsmith-stretch/LICENSE.txt",
                "vendor/signalsmith-stretch/signalsmith-linear/LICENSE.txt",
            ],
            cxxSettings: [.define("SIGNALSMITH_USE_ACCELERATE")],
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        .target(name: "ObjCSupport"),
        .target(name: "VoiceChangerKit", dependencies: ["VoiceDSP", "ObjCSupport"]),
        .executableTarget(name: "VoiceChanger", dependencies: ["VoiceChangerKit"]),
        .testTarget(name: "VoiceChangerKitTests", dependencies: ["VoiceChangerKit", "VoiceDSP", "ObjCSupport"]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
