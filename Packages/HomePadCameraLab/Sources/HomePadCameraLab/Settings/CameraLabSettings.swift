import Foundation
import HomePadCore

/// Settings owned by Camera Lab. Choices are curated (a few levels and presets)
/// instead of free-form numbers, the way iOS Settings does it.
enum CameraLabSettings {
    // Ask About This
    static let speakAnswers = SettingKey<Bool>("cameralab.ask.speakAnswers", default: true)

    // Groceries
    static let groceryListName = SettingKey<String>("cameralab.groceries.listName", default: "Groceries")

    // Security Camera
    static let securityEnabled = SettingKey<Bool>("cameralab.security.enabled", default: false)
    static let securityCamera = SettingKey<CameraPosition>("cameralab.security.camera", default: .back)
    static let securityPort = SettingKey<Int>("cameralab.security.port", default: 8081)
    static let securitySensitivity = SettingKey<MotionSensitivity>("cameralab.security.sensitivity", default: .medium)
    static let securitySchedule = SettingKey<SecuritySchedule>("cameralab.security.schedule", default: .always)
    static let securityRequirePerson = SettingKey<Bool>("cameralab.security.requirePerson", default: true)
    static let securitySnapshotLimit = SettingKey<Int>("cameralab.security.snapshotLimit", default: 50)

    // Timelapse
    static let timelapseInterval = SettingKey<TimelapseInterval>("cameralab.timelapse.interval", default: .fiveMinutes)
    static let timelapseAlbum = SettingKey<String>("cameralab.timelapse.album", default: "HomePad Timelapse")
    static let timelapseRunning = SettingKey<Bool>("cameralab.timelapse.running", default: false)

    /// Ports offered in the port picker. 8081 avoids Home Assistant's 8123 and common 8080 servers.
    static let portChoices = [8081, 8080, 8090, 8888, 9000]
    /// Snapshot buffer sizes offered in Settings.
    static let snapshotLimitChoices = [20, 50, 100, 200]
}

/// Keychain accounts for Camera Lab secrets. Both the stream token and the
/// Home Assistant webhook URL grant access, so neither goes in plain settings.
enum CameraLabSecrets {
    static let streamToken = "cameralab.security.streamToken"
    static let webhookURL = "cameralab.security.webhookURL"
}
