import Foundation
import HomePadCore

/// A one-tap timer length, shown in the Timers app and Control Center.
public struct TimerPreset: Codable, Hashable, Sendable, Identifiable {
    public var seconds: TimeInterval
    public var id: TimeInterval { seconds }

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public var title: String { TimerFormat.spoken(seconds) }

    /// Lengths offered in Settings. Customization is a pick from this list, not free entry.
    public static let catalog: [TimerPreset] = [30, 60, 120, 180, 240, 300, 390, 420, 480, 600, 720, 900, 1200, 1500,
                                                1800, 2700, 3600, 5400, 7200].map { TimerPreset(seconds: $0) }

    public static let defaults: [TimerPreset] = [60, 180, 300, 600, 900, 1800].map { TimerPreset(seconds: $0) }
}

/// Which end of a ranged time ("3 to 5 minutes") a step's timer chip starts.
public enum RangedTimeChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case shortest, longest
    public var id: String { rawValue }
    public var title: String { self == .shortest ? "Shortest" : "Longest" }
}

/// Kitchen settings, named `kitchen.<setting>`.
public enum KitchenSettings {
    /// Up to six timer presets.
    public static let presets = SettingKey<[TimerPreset]>("kitchen.timerPresets", default: TimerPreset.defaults, syncsWithICloud: true)
    public static let chime = SettingKey<ChimeSound>("kitchen.chime", default: .chime, syncsWithICloud: true)
    /// Servings new cooking sessions start at. Zero keeps each recipe's own servings.
    public static let defaultServings = SettingKey<Int>("kitchen.defaultServings", default: 0, syncsWithICloud: true)
    /// The servings people pick from, for the default and for a planned meal.
    public static let servingChoices = [1, 2, 3, 4, 6, 8]
    public static let unitSystem = SettingKey<UnitSystem>("kitchen.unitSystem", default: .original, syncsWithICloud: true)
    public static let rangedTime = SettingKey<RangedTimeChoice>("kitchen.rangedTime", default: .shortest, syncsWithICloud: true)
    /// Ring timers and wake-up alarms with AlarmKit while HomePad is in the background.
    public static let backgroundAlarms = SettingKey<Bool>("kitchen.backgroundAlarms", default: true)
    public static let liveActivities = SettingKey<Bool>("kitchen.liveActivities", default: true)

    /// Most presets the Timers app and Control Center show.
    public static let maxPresets = 6
}

/// Kitchen secrets, kept in `services.keychain` and never in settings.
public enum KitchenSecrets {
    /// An optional TheMealDB supporter key. Without one, search uses TheMealDB's free public key.
    public static let mealDBKey = "kitchen.mealdb.supporterKey"
}
