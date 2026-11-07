import Foundation

/// Setting keys that more than one module reads. Module-private keys live in
/// their own package, named `<module>.<setting>`.
public enum CoreSettings {
    // Privacy switches (Control Center toggles them, Presence/Assistant obey them).
    public static let cameraEnabled = SettingKey<Bool>("core.privacy.cameraEnabled", default: true)
    public static let microphoneEnabled = SettingKey<Bool>("core.privacy.microphoneEnabled", default: true)

    // Sensing features.
    public static let faceRecognitionEnabled = SettingKey<Bool>("core.presence.faceRecognition", default: true)
    /// On by default: a raised palm stops a ringing timer.
    /// Hands are only looked for while someone is within reach.
    public static let handGesturesEnabled = SettingKey<Bool>("core.presence.handGestures", default: true)
    /// Off by default: a raised palm also plays or pauses music. Hands near the
    /// iPad paused music too easily.
    public static let palmControlsMusic = SettingKey<Bool>("core.presence.palmControlsMusic", default: false)
    public static let soundAlertsEnabled = SettingKey<Bool>("core.presence.soundAlerts", default: true)

    // Assistant.
    public static let wakeWordEnabled = SettingKey<Bool>("core.assistant.wakeWord", default: true)
    public static let wakePhrase = SettingKey<String>("core.assistant.wakePhrase", default: "Hey HomePad", syncsWithICloud: true)

    // Display and kiosk.
    /// The kind of the household's current face. Each HomePad sets it from the
    /// faces the household shares (the Faces module), so it is not synced itself.
    public static let defaultFaceID = SettingKey<String>("core.display.defaultFace", default: "faces.modular")
    public static let nightModeAutomatic = SettingKey<Bool>("core.display.nightModeAuto", default: true)
    /// Seconds without touch before returning to the face.
    public static let returnToFaceAfter = SettingKey<Double>("core.display.returnToFaceAfter", default: 60)
    /// Minutes with nobody present before the screen goes to sleep (near-black).
    public static let sleepAfterMinutes = SettingKey<Double>("core.display.sleepAfterMinutes", default: 10)

    // Household identity for the local-network peer link (intercom, sharing).
    public static let householdName = SettingKey<String>("core.household.name", default: "Home", syncsWithICloud: true)
    /// Seconds HomePad stays in a person's profile after it last detected them
    /// (`MemberSession`). Set in Settings > Presence & Privacy.
    public static let signOutAfter = SettingKey<Double>("core.household.signOutAfter", default: 30)
    /// The choices Settings offers for `signOutAfter`.
    public static let signOutAfterChoices: [Double] = [10, 30, 60, 120, 300]
}
