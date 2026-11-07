import Foundation
import HomePadCore

/// Module-private setting keys. Shared switches (camera, microphone, face
/// recognition, hand gestures, sound alerts) live in `CoreSettings`.
enum PresenceSettings {
    /// How eagerly presence and motion sensing react.
    static let sensitivity = SettingKey<SensingSensitivity>("presence.sensitivity", default: .medium)
    /// How eagerly sound alerts fire.
    static let soundSensitivity = SettingKey<SensingSensitivity>("presence.soundSensitivity", default: .medium)
    /// How sure face recognition must be before it unlocks personal content.
    static let recognitionStrictness = SettingKey<RecognitionStrictness>("presence.recognitionStrictness", default: .standard)
    /// Use the TrueDepth camera when the iPad has one. Off forces the RGB path.
    static let useTrueDepth = SettingKey<Bool>("presence.useTrueDepth", default: true)
    /// Post `.motionDetected` events for other modules (Flow face, kiosk wake).
    static let motionEvents = SettingKey<Bool>("presence.motionEvents", default: true)
    /// Listen for AirPods nods and shakes when a yes or no question is likely.
    static let headGestures = SettingKey<Bool>("presence.headGestures", default: true)
    /// Which sound kinds raise alerts, by `SoundAlertKind.rawValue`.
    static let alertSounds = SettingKey<[String]>(
        "presence.alertSounds", default: SoundAlertKind.allCases.map(\.rawValue)
    )
    /// Mirror app choices.
    static let mirrorRingLight = SettingKey<RingLightLevel>("presence.mirror.ringLight", default: .medium)
    static let mirrorRingTone = SettingKey<RingLightTone>("presence.mirror.ringTone", default: .neutral)
    static let mirrorFraming = SettingKey<MirrorFraming>("presence.mirror.framing", default: .closeUp)
}

/// A curated sensitivity level. Each level maps to tuned thresholds so the
/// settings never expose raw numbers.
public enum SensingSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Per-cell luma change (0...255) that counts as a changed cell.
    var motionPixelDelta: Int {
        switch self {
        case .low: 26
        case .medium: 18
        case .high: 12
        }
    }

    /// Fraction of grid cells that must change to count as motion.
    var motionAreaFraction: Double {
        switch self {
        case .low: 0.06
        case .medium: 0.03
        case .high: 0.015
        }
    }

    /// Smallest face, as a fraction of the image width, that the RGB path counts.
    var minimumFaceWidth: Double {
        switch self {
        case .low: 0.06
        case .medium: 0.035
        case .high: 0.02
        }
    }

    /// Minimum classifier confidence for a sound alert.
    var soundConfidence: Double {
        switch self {
        case .low: 0.8
        case .medium: 0.65
        case .high: 0.5
        }
    }

    /// Microphone level (0...1) that counts as someone talking or moving nearby.
    var voiceActivityLevel: Double {
        switch self {
        case .low: 0.12
        case .medium: 0.07
        case .high: 0.04
        }
    }
}

/// How sure face recognition must be. Curated presets over the matcher and voter.
public enum RecognitionStrictness: String, Codable, CaseIterable, Identifiable, Sendable {
    case relaxed, standard, strict

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .standard: "Standard"
        case .strict: "Strict"
        }
    }

    var matcher: FaceMatcher {
        switch self {
        case .relaxed: FaceMatcher(acceptThreshold: 0.76, margin: 0.03)
        case .standard: FaceMatcher(acceptThreshold: 0.82, margin: 0.04)
        case .strict: FaceMatcher(acceptThreshold: 0.88, margin: 0.06)
        }
    }

    var voter: RecognitionVoter {
        switch self {
        case .relaxed: RecognitionVoter(windowSize: 6, requiredVotes: 3)
        case .standard: RecognitionVoter(windowSize: 7, requiredVotes: 4)
        case .strict: RecognitionVoter(windowSize: 8, requiredVotes: 6)
        }
    }

    /// Seconds between samples while a match is likely (`RecognitionCadence`).
    /// Votes 0.2 s apart cover less time than votes 0.5 s apart, so Relaxed and
    /// Standard trade some of that span for speed (their votes cover at least
    /// 0.4 s and 0.6 s). Strict keeps the slow rate, so its six votes still
    /// cover at least 2.5 s, as before.
    var fastSampleInterval: TimeInterval {
        switch self {
        case .relaxed, .standard: 0.2
        case .strict: RecognitionCadence.slowInterval
        }
    }
}
