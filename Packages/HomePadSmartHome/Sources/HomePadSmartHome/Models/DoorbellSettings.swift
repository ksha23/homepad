import Foundation

/// Which entities make up the front-door system. Nil fields are picked automatically:
/// any doorbell event or sensor rings, the camera on the same device (or the first
/// doorbell camera) shows, and the lock in the same room unlocks.
struct DoorbellSettings: Codable, Hashable, Sendable {
    /// Unified ID of an extra accessory that counts as a doorbell press,
    /// for example `ha:binary_sensor.front_button`.
    var triggerID: String?
    /// Unified camera ID to show when the doorbell rings.
    var cameraID: String?
    /// Unified lock ID for the overlay's unlock button.
    var lockID: String?
    /// The overlay closes by itself after this many seconds without interaction.
    var autoDismissSeconds: Double = 60

    static let dismissChoices: [Double] = [30, 60, 120, 300]

    /// The settings with each picked ID as this HomePad knows it.
    func localized(by localID: (String) -> String) -> DoorbellSettings {
        var settings = self
        settings.triggerID = triggerID.map(localID)
        settings.cameraID = cameraID.map(localID)
        settings.lockID = lockID.map(localID)
        return settings
    }
}
