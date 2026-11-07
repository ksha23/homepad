import HomePadCore

/// Picks the face to show in ambient mode. First registered match wins:
/// a requested face (`.showFace` event or launch argument), the active member's
/// `preferences["faceID"]`, `CoreSettings.defaultFaceID`, then the first
/// registered face. The shell always registers its built-in clock, so there
/// is a face whenever the shell is loaded.
enum FaceResolver {
    /// ID of the shell's built-in clock face.
    static let builtInClockID = "shell.clock"

    static func resolve(override: String?, memberPreference: String?, defaultID: String, available: [String]) -> String? {
        let candidates = [override, memberPreference, defaultID].compactMap { $0 }
        return candidates.first(where: available.contains) ?? available.first
    }

    /// The face `CurrentFaceView` draws right now, on screen or under the Home
    /// Screen. The kiosk status reports the same one.
    @MainActor
    static func current(navigator: ShellNavigator, household: Household, settings: SettingsStore) -> String? {
        resolve(
            override: navigator.faceOverride,
            memberPreference: household.activeMember?.preferences[HouseholdMember.facePreferenceKey]?.stringValue,
            defaultID: settings[CoreSettings.defaultFaceID],
            available: navigator.registry.faces.map(\.id)
        )
    }
}
