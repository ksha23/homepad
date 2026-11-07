import HomePadCore

/// Settings keys private to the shell. Keys shared with other modules live in
/// `CoreSettings` (timing, night mode automatic, privacy switches, default face).
enum ShellSettings {
    // Kiosk and display.
    static let keepScreenOn = SettingKey<Bool>("shell.kiosk.keepScreenOn", default: true)
    /// Minutes with nobody seen before the display dims.
    static let dimAfterMinutes = SettingKey<Double>("shell.kiosk.dimAfterMinutes", default: 2)
    static let nightSchedule = SettingKey<NightSchedule>("shell.kiosk.nightSchedule", default: .standard)
    /// Night mode right now, regardless of schedule or room light (Control Center toggle).
    static let nightModeForced = SettingKey<Bool>("shell.kiosk.nightModeForced", default: false)
    static let brightnessLevels = SettingKey<BrightnessLevels>("shell.kiosk.brightness", default: .standard)
    /// Nudge brightness up in bright rooms and down in dark ones.
    static let adaptToRoomLight = SettingKey<Bool>("shell.kiosk.adaptToRoomLight", default: true)
    /// Let iPadOS auto-brightness drive the screen while it is in use or showing
    /// the face. HomePad then only dims for nobody nearby, night and sleep.
    static let followSystemBrightness = SettingKey<Bool>("shell.kiosk.followSystemBrightness", default: true)
    static let burnInProtection = SettingKey<Bool>("shell.kiosk.burnInProtection", default: true)
    /// Largest burn-in shift in points.
    static let burnInAmplitude = SettingKey<Double>("shell.kiosk.burnInAmplitude", default: 8)
    static let chargingWarning = SettingKey<Bool>("shell.kiosk.chargingWarning", default: true)
    static let textSize = SettingKey<TextSizeChoice>("shell.display.textSize", default: .system)
    /// Light, dark, or the iPad's own. Dark by default, the look HomePad was made in.
    static let appearance = SettingKey<AppearanceChoice>("shell.display.appearance", default: .dark)
    /// The close button top right in every app. Off: a swipe up from the bottom edge closes apps.
    static let showsCloseButton = SettingKey<Bool>("shell.display.showsCloseButton", default: false)

    // Surfaces.
    static let onboardingCompleted = SettingKey<Bool>("shell.onboardingCompleted", default: false)
    /// Setup asked for camera, microphone and speech recognition access.
    static let askedSensingPermissions = SettingKey<Bool>("shell.askedSensingPermissions", default: false)
    static let controlCenterLayout = SettingKey<ControlCenterLayout?>("shell.controlCenter.layout", default: nil)

    /// Home Screen layout for one member, or for guests when `memberID` is nil.
    static func homeScreenLayout(for memberID: HouseholdMember.ID?) -> SettingKey<HomeScreenLayout?> {
        SettingKey("shell.homeScreen.\(memberID?.uuidString ?? "guest")", default: nil)
    }

    /// Wallpaper for one member, or for guests when `memberID` is nil.
    static func wallpaper(for memberID: HouseholdMember.ID?) -> SettingKey<WallpaperChoice> {
        SettingKey("shell.wallpaper.\(memberID?.uuidString ?? "guest")", default: .standard)
    }
}
