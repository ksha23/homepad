import HomePadCore

/// The Presence settings the per-frame path uses.
struct FrameSettings {
    var sensitivity: SensingSensitivity
    var handGestures: Bool
    var motionEvents: Bool
    var useTrueDepth: Bool

    @MainActor
    init(_ settings: SettingsStore) {
        sensitivity = settings[PresenceSettings.sensitivity]
        handGestures = settings[CoreSettings.handGesturesEnabled]
        motionEvents = settings[PresenceSettings.motionEvents]
        useTrueDepth = settings[PresenceSettings.useTrueDepth]
    }
}
