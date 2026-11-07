import Foundation
import HomePadCore
import Observation

/// Stores the Smart Rotation rules in settings. Connect shares them with the
/// household's other HomePads (`FaceSharing`).
@MainActor
@Observable
final class RotationStore {
    static let storageKey = SettingKey<RotationSettings>("faces.auto.rules", default: .defaults)

    @ObservationIgnored private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var current: RotationSettings {
        get { settings[Self.storageKey] }
        set { settings[Self.storageKey] = newValue }
    }

    func restoreDefaults() {
        settings.reset(Self.storageKey)
    }
}
