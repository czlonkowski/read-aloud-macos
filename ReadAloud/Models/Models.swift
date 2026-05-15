import Foundation

enum SpokenLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case english = "en"
    case polish  = "pl"

    var id: String { rawValue }

    var bcp47: String {
        switch self {
        case .english: "en-US"
        case .polish:  "pl-PL"
        }
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .polish:  "Polish"
        }
    }
}

enum EngineChoice: String, Codable, CaseIterable, Identifiable, Hashable {
    case apple
    case sidecar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:   "Apple system voice"
        case .sidecar: "Local neural model"
        }
    }
}

struct VoiceSelection: Codable, Hashable {
    /// For `.apple` engine: the AVSpeechSynthesisVoice identifier.
    /// For `.sidecar` engine: a voice id understood by the sidecar (e.g. "af_heart").
    var id: String
    /// User-visible label.
    var displayName: String
}

enum PlaybackState: Equatable {
    case idle
    case preparing
    case speaking(progress: Double)
    case paused
}

struct ReadRequest: Identifiable {
    let id = UUID()
    let text: String
    let language: SpokenLanguage
    let sourceBundleID: String?
    let createdAt: Date
}
