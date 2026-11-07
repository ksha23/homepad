import Foundation

/// Debug launch arguments for simulator screenshots and UI checks, next to the shell's
/// `-HomePadOpenApp`. Release builds ignore them.
///
///     -HomePadSmartHomeAccessory demo:light.kitchen   open the Home app on this accessory's controls
///     -HomePadSmartHomeRoom "Living Room"             open the Home app on this room
///     -HomePadSmartHomeCamera demo:camera.yard        open the Home app on this camera, full screen
///     -HomePadRingDoorbell demo:camera.front          ring the doorbell two seconds after launch
///     -HomePadDashboardFixture YES                    show a local stand-in page in Dashboards
///     -HomePadSmartHomeSettings YES                   show the Smart Home settings pane on top
///     -HomePadSmartHomeSettingsSection device         with it, scroll to This HomePad in Home Assistant
///     -HomePadSmartHomeDevicePreview YES              draw that section as registered, with no network
///     -HomePadSmartHomeFavorites "demo:lock.ultra,demo:light.desk"   use these favorites
///     -HomePadSmartHomeAdjusting demo:light.desk=45   draw that accessory's tiles mid-drag at 45 percent
struct SmartHomeLaunchOptions {
    var accessoryID: String?
    var room: String?
    var cameraID: String?
    var doorbellCameraID: String?
    var dashboardFixtureURL: URL?
    var showsSettings = false
    var settingsSection: String?
    var devicePreview = false
    var favoriteIDs: [String]?
    var adjusting: (accessoryID: String, level: Double)?

    static var current: SmartHomeLaunchOptions {
        #if DEBUG
        let defaults = UserDefaults.standard
        return SmartHomeLaunchOptions(
            accessoryID: defaults.string(forKey: "HomePadSmartHomeAccessory"),
            room: defaults.string(forKey: "HomePadSmartHomeRoom"),
            cameraID: defaults.string(forKey: "HomePadSmartHomeCamera"),
            doorbellCameraID: defaults.string(forKey: "HomePadRingDoorbell"),
            dashboardFixtureURL: defaults.bool(forKey: "HomePadDashboardFixture")
                ? Bundle.module.url(forResource: "DashboardFixture", withExtension: "html") : nil,
            showsSettings: defaults.bool(forKey: "HomePadSmartHomeSettings"),
            settingsSection: defaults.string(forKey: "HomePadSmartHomeSettingsSection"),
            devicePreview: defaults.bool(forKey: "HomePadSmartHomeDevicePreview"),
            favoriteIDs: defaults.string(forKey: "HomePadSmartHomeFavorites")?.split(separator: ",").map(String.init),
            adjusting: defaults.string(forKey: "HomePadSmartHomeAdjusting").flatMap(Self.adjusting)
        )
        #else
        return SmartHomeLaunchOptions()
        #endif
    }

    /// Read once, for views that check it while drawing.
    static let atLaunch = current

    /// "demo:light.desk=45" becomes that accessory at 0.45.
    private static func adjusting(_ value: String) -> (accessoryID: String, level: Double)? {
        guard let split = value.lastIndex(of: "="), let percent = Double(value[value.index(after: split)...]) else { return nil }
        return (String(value[..<split]), percent / 100)
    }
}
