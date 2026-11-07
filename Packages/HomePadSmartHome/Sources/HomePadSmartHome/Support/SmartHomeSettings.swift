import HomePadCore

/// Settings owned by the Smart Home module. The Home Assistant token is a secret
/// and lives in the keychain under `SmartHomeSettings.homeAssistantTokenAccount`.
enum SmartHomeSettings {
    /// Base URL of the Home Assistant instance, for example `http://homeassistant.local:8123`.
    static let homeAssistantURL = SettingKey<String>("smarthome.homeAssistant.url", default: "")
    static let homeAssistantTokenAccount = "smarthome.homeAssistant.token"

    /// Whether this HomePad is a device in Home Assistant, with sensors and
    /// commands. Off until someone turns it on. Not synced: each HomePad decides.
    static let homeAssistantDeviceEnabled = SettingKey<Bool>("smarthome.homeAssistant.device.enabled", default: false)
    /// The device ID this HomePad registers with, made once. Not synced, so every
    /// HomePad is its own device, and kept after Remove, so adding it again
    /// replaces whatever Home Assistant still had.
    static let homeAssistantDeviceID = SettingKey<String>("smarthome.homeAssistant.device.id", default: "")
    /// Keychain account, on this iPad only, for the registration and its webhook ID.
    static let homeAssistantDeviceRegistrationAccount = "smarthome.homeAssistant.device.registration"

    /// Set once the person chose to connect Apple Home, so the HomeKit permission
    /// prompt only appears after they asked for it.
    static let homeKitEnabled = SettingKey<Bool>("smarthome.homeKit.enabled", default: false)
    /// The HomeKit home to show. Empty means the first home.
    static let homeKitHomeID = SettingKey<String>("smarthome.homeKit.homeID", default: "")

    /// Favorite accessories in display order. Nil until the person edits favorites,
    /// which means sensible defaults are picked automatically. Shared by the
    /// household's HomePads (`SmartHomeSharing`), not iCloud. IDs may be
    /// another HomePad's, so read them through `localID(for:)`.
    static let favoriteAccessoryIDs = SettingKey<[String]?>("smarthome.favorites.accessories", default: nil)
    /// Favorite scenes in display order, shown in the Home app. Nil means none.
    static let favoriteSceneIDs = SettingKey<[String]?>("smarthome.favorites.scenes", default: nil)

    /// The HomeKit directory of every other HomePad, by its device ID, as it
    /// arrived with the shared setup. Not synced: each HomePad keeps what it heard.
    static let homeKitOtherDirectories = SettingKey<[String: HomeKitDirectory]>("smarthome.homeKit.otherHomePads", default: [:])
    /// Pairs of another HomePad's HomeKit ID and this HomePad's own that were
    /// found once, kept so they hold through a rename. Not synced.
    static let homeKitTranslations = SettingKey<[String: String]>("smarthome.homeKit.translations", default: [:])

    static let layout = SettingKey<HomeLayout>("smarthome.layout", default: HomeLayout(), syncsWithICloud: true)
    static let doorbell = SettingKey<DoorbellSettings>("smarthome.doorbell", default: DoorbellSettings(), syncsWithICloud: true)
    /// Whether this HomePad plays a chime when the doorbell rings. Each HomePad
    /// keeps its own, so a bedroom one can stay silent.
    static let doorbellChime = SettingKey<Bool>("smarthome.doorbell.chime", default: true)
    /// Keeps the chime silent in night mode, as intercom does.
    static let doorbellChimeQuietAtNight = SettingKey<Bool>("smarthome.doorbell.chimeQuietAtNight", default: true)
    static let dashboards = SettingKey<DashboardSettings>("smarthome.dashboards", default: DashboardSettings(), syncsWithICloud: true)
}
