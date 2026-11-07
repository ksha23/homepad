import Foundation

/// A procedurally generated sleep or focus sound.
public enum AmbientSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case white
    case pink
    case brown
    case rain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .white: "White Noise"
        case .pink: "Pink Noise"
        case .brown: "Brown Noise"
        case .rain: "Rain"
        }
    }

    public var detail: String {
        switch self {
        case .white: "Bright and even, masks voices"
        case .pink: "Softer, like steady wind"
        case .brown: "Deep rumble, like a distant waterfall"
        case .rain: "Gentle rain with soft drops"
        }
    }

    public var systemImage: String {
        switch self {
        case .white: "waveform"
        case .pink: "wind"
        case .brown: "water.waves"
        case .rain: "cloud.rain.fill"
        }
    }
}

/// A curated combination of sound, level and timer, like "Rainy Night".
/// People choose which presets show, not how they are built.
public struct SleepPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sound: AmbientSound
    /// Relative loudness 0...1.
    public let volume: Double
    /// Sleep timer in minutes, nil to use the default from settings.
    public let timerMinutes: Int?

    /// Every preset HomePad offers.
    public static let all: [SleepPreset] = [
        SleepPreset(id: "rainy-night", title: "Rainy Night", sound: .rain, volume: 0.6, timerMinutes: nil),
        SleepPreset(id: "deep-sleep", title: "Deep Sleep", sound: .brown, volume: 0.55, timerMinutes: nil),
        SleepPreset(id: "soft-static", title: "Soft Static", sound: .pink, volume: 0.5, timerMinutes: nil),
        SleepPreset(id: "white-noise", title: "White Noise", sound: .white, volume: 0.4, timerMinutes: nil),
        SleepPreset(id: "power-nap", title: "Power Nap", sound: .pink, volume: 0.45, timerMinutes: 20),
        SleepPreset(id: "focus", title: "Focus", sound: .brown, volume: 0.4, timerMinutes: 60),
        SleepPreset(id: "baby-sleep", title: "Baby Sleep", sound: .white, volume: 0.5, timerMinutes: nil),
    ]

    static let defaultIDs = ["rainy-night", "deep-sleep", "soft-static", "white-noise"]

    public static func preset(_ id: String) -> SleepPreset? {
        all.first { $0.id == id }
    }
}
