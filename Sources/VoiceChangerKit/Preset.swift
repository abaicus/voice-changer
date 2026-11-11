import Foundation
import VoiceDSP

public struct VoiceParameters: Codable, Equatable, Sendable {
    public var pitch: Float = 0
    public var formant: Float = 0
    public var robotMix: Float = 0
    public var robotHz: Float = 80
    public var distortion: Float = 0
    public var lowGain: Float = 0
    public var midGain: Float = 0
    public var highGain: Float = 0
    public var lowCut: Float = 20
    public var highCut: Float = 20000
    public var reverbMix: Float = 0
    public var reverbSize: Float = 0.5
    public var gateThreshold: Float = -80
    public var outputGain: Float = 0

    public init() {}

    // Missing keys fall back to defaults so presets saved by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, _ fallback: Float) throws -> Float {
            try c.decodeIfPresent(Float.self, forKey: key) ?? fallback
        }
        pitch = try value(.pitch, pitch)
        formant = try value(.formant, formant)
        robotMix = try value(.robotMix, robotMix)
        robotHz = try value(.robotHz, robotHz)
        distortion = try value(.distortion, distortion)
        lowGain = try value(.lowGain, lowGain)
        midGain = try value(.midGain, midGain)
        highGain = try value(.highGain, highGain)
        lowCut = try value(.lowCut, lowCut)
        highCut = try value(.highCut, highCut)
        reverbMix = try value(.reverbMix, reverbMix)
        reverbSize = try value(.reverbSize, reverbSize)
        gateThreshold = try value(.gateThreshold, gateThreshold)
        outputGain = try value(.outputGain, outputGain)
    }

    func dspParams(bypass: Bool) -> vc_params {
        vc_params(
            pitchSemitones: pitch, formantSemitones: formant, robotMix: robotMix, robotHz: robotHz,
            distortion: distortion, lowGainDb: lowGain, midGainDb: midGain, highGainDb: highGain,
            lowCutHz: lowCut, highCutHz: highCut, reverbMix: reverbMix, reverbSize: reverbSize,
            gateThresholdDb: gateThreshold, outputGainDb: outputGain, bypass: bypass)
    }
}

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var params: VoiceParameters

    public init(id: String = UUID().uuidString, name: String, params: VoiceParameters) {
        self.id = id
        self.name = name
        self.params = params
    }

    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    private static func builtIn(_ key: String, _ name: String, _ configure: (inout VoiceParameters) -> Void) -> Preset {
        var params = VoiceParameters()
        configure(&params)
        return Preset(id: "builtin.\(key)", name: name, params: params)
    }

    public static let builtIns: [Preset] = [
        builtIn("normal", "Normal") { _ in },
        builtIn("deep", "Deep") { $0.pitch = -4; $0.formant = -2.5 },
        builtIn("high", "High") { $0.pitch = 5; $0.formant = 2.5 },
        builtIn("chipmunk", "Chipmunk") { $0.pitch = 9; $0.formant = 6 },
        builtIn("monster", "Monster") { $0.pitch = -8; $0.formant = -5; $0.distortion = 0.25; $0.lowGain = 4 },
        builtIn("robot", "Robot") { $0.robotMix = 0.9; $0.robotHz = 70; $0.distortion = 0.15; $0.highCut = 6000 },
        builtIn("telephone", "Telephone") { $0.lowCut = 400; $0.highCut = 3200; $0.distortion = 0.2; $0.midGain = 4 },
        builtIn("cave", "Cave") { $0.pitch = -1; $0.reverbMix = 0.55; $0.reverbSize = 0.9 },
    ]
}

extension Preset {
    public var symbolName: String {
        switch id {
        case "builtin.normal": "person.wave.2.fill"
        case "builtin.deep": "arrow.down.circle.fill"
        case "builtin.high": "arrow.up.circle.fill"
        case "builtin.chipmunk": "hare.fill"
        case "builtin.monster": "flame.fill"
        case "builtin.robot": "cpu.fill"
        case "builtin.telephone": "phone.fill"
        case "builtin.cave": "mountain.2.fill"
        default: "slider.horizontal.3"
        }
    }
}
