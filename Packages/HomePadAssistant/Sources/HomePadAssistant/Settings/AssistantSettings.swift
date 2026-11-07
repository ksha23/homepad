import Foundation
import HomePadCore

/// Setting keys owned by the assistant. Choices are curated (a few presets
/// each) so the assistant sounds and behaves well without any setup.
public enum AssistantSettings {
    /// Per-provider switches, base URL overrides and chosen models, keyed by provider ID.
    static let providers = SettingKey<[String: ProviderSettings]>("assistant.providers", default: [:])
    /// The provider used when the request and the person have no preference. Empty means automatic.
    static let defaultProvider = SettingKey<String>("assistant.defaultProvider", default: "", syncsWithICloud: true)
    /// Providers to try, in order, when the preferred one fails.
    static let fallbackOrder = SettingKey<[String]>("assistant.fallbackOrder", default: [], syncsWithICloud: true)
    /// Household default answer style. People can pick their own.
    static let personality = SettingKey<Personality>("assistant.personality", default: .friendly, syncsWithICloud: true)

    static let speakResponses = SettingKey<Bool>("assistant.voice.speak", default: true)
    /// Identifier of an installed system voice. Empty picks the best installed voice.
    static let voiceIdentifier = SettingKey<String>("assistant.voice.identifier", default: "")
    static let speakingRate = SettingKey<SpeakingRate>("assistant.voice.rate", default: .normal)
    static let voiceEngine = SettingKey<VoiceEngine>("assistant.voice.engine", default: .system)
    static let cloudVoice = SettingKey<CloudVoice>("assistant.voice.cloudVoice", default: .marin)
    static let naturalVoice = SettingKey<NaturalVoice>("assistant.voice.natural", default: .heart)
    static let listeningPatience = SettingKey<ListeningPatience>("assistant.voice.patience", default: .normal)
    /// Keep listening after an answer that ends with a question.
    static let followUpListening = SettingKey<Bool>("assistant.voice.followUp", default: true)
}

/// A provider's user choices. Nil fields fall back to the preset.
struct ProviderSettings: Codable, Hashable, Sendable {
    var isEnabled: Bool?
    var baseURL: String?
    var model: String?
}

/// How the assistant phrases answers.
public enum Personality: String, Codable, CaseIterable, Identifiable, Sendable {
    case concise, friendly, detailed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .concise: "Concise"
        case .friendly: "Friendly"
        case .detailed: "Detailed"
        }
    }

    public var summary: String {
        switch self {
        case .concise: "Short, direct answers."
        case .friendly: "Warm and conversational."
        case .detailed: "Thorough answers with context."
        }
    }

    /// The style line added to the system prompt.
    var instruction: String {
        switch self {
        case .concise: "Answer in one short sentence when you can. Skip pleasantries."
        case .friendly: "Be warm and natural, like a helpful friend. Keep answers to two or three sentences."
        case .detailed: "Give complete, well organized answers with useful context, while staying easy to follow when heard aloud."
        }
    }
}

/// Speaking speed, in a few steps like iOS.
public enum SpeakingRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case slower, normal, faster

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    /// Multiplier on the system default speech rate.
    var multiplier: Float {
        switch self {
        case .slower: 0.85
        case .normal: 1.0
        case .faster: 1.15
        }
    }
}

/// Which engine reads answers aloud.
public enum VoiceEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Installed system voices, the best one automatically. Private, works offline.
    case system
    /// Kokoro, a neural voice that runs on the iPad. Private and offline, after a
    /// one-time 330 MB download that starts when this is chosen.
    case natural
    /// OpenAI text to speech. Needs an OpenAI key and sends answers to OpenAI.
    case openAI

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: "Apple"
        case .natural: "Natural"
        case .openAI: "OpenAI"
        }
    }
}

/// The Natural voice's voices: Kokoro's best rated, American then British.
public enum NaturalVoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case heart, bella, nicole, sarah, michael, fenrir, puck, emma, george, fable

    public var id: String { rawValue }

    public var displayName: String {
        let name = rawValue.capitalized
        return isBritish ? "\(name) (British)" : name
    }

    var isBritish: Bool { [.emma, .george, .fable].contains(self) }

    /// The voice's key in the bundled voices file: accent and gender, then the name.
    var fileKey: String {
        let isFemale: Bool = [.heart, .bella, .nicole, .sarah, .emma].contains(self)
        return (isBritish ? "b" : "a") + (isFemale ? "f" : "m") + "_" + rawValue
    }
}

/// A short, curated list of OpenAI voices.
public enum CloudVoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case marin, cedar, coral, sage, verse, alloy

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

/// How long a pause ends a spoken request.
public enum ListeningPatience: String, Codable, CaseIterable, Identifiable, Sendable {
    case quick, normal, relaxed

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    /// Seconds of silence after the last recognized word.
    var silence: TimeInterval {
        switch self {
        case .quick: 0.8
        case .normal: 1.3
        case .relaxed: 2.2
        }
    }
}
