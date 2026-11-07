import Foundation

public extension CoreSettings {
    /// Quiet hours, switched from Control Center. While on, modules should skip
    /// non-urgent sounds (chimes, announcements, spoken answers when a visual one
    /// will do) and keep the screen calm. Safety alerts such as smoke alarms and
    /// timers still sound.
    static let quietHoursEnabled = SettingKey<Bool>("core.display.quietHours", default: false)
}
