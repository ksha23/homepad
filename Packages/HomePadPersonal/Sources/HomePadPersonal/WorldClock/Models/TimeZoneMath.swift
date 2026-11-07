import Foundation

/// Pure time zone arithmetic for the World Clock, its widget and the assistant.
/// Every function takes the instant and zones explicitly so tests can pin them.
public enum TimeZoneMath {
    /// Which calendar day a city is on compared with home.
    public enum DayRelation: Equatable, Sendable {
        case yesterday, today, tomorrow

        public var title: String {
            switch self {
            case .yesterday: "Yesterday"
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            }
        }
    }

    /// Seconds `zone` is ahead of `home` at `date`. Negative when behind.
    /// Accounts for daylight saving time in both zones at that instant.
    public static func offset(of zone: TimeZone, from home: TimeZone, at date: Date) -> Int {
        zone.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)
    }

    /// "+6 hrs", "−3 hrs", "+5 hrs 30 min", "+1 hr", "Same time".
    public static func offsetText(seconds: Int) -> String {
        guard seconds != 0 else { return "Same time" }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hr" : "hrs")") }
        if minutes > 0 { parts.append("\(minutes) min") }
        return sign + parts.joined(separator: " ")
    }

    /// Whether it is yesterday, today or tomorrow in `zone` relative to `home`.
    public static func dayRelation(of zone: TimeZone, from home: TimeZone, at date: Date) -> DayRelation {
        let homeDay = dayNumber(of: date, in: home)
        let zoneDay = dayNumber(of: date, in: zone)
        if zoneDay > homeDay { return .tomorrow }
        if zoneDay < homeDay { return .yesterday }
        return .today
    }

    /// "Today, +6 hrs" style subtitle.
    public static func subtitle(for zone: TimeZone, from home: TimeZone, at date: Date) -> String {
        "\(dayRelation(of: zone, from: home, at: date).title), \(offsetText(seconds: offset(of: zone, from: home, at: date)))"
    }

    /// Local wall-clock hour (0...23) and minute in `zone`.
    public static func wallClock(at date: Date, in zone: TimeZone) -> (hour: Int, minute: Int, second: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// True between 6 AM and 6 PM local time. Drives the light and dark clock faces.
    public static func isDaytime(at date: Date, in zone: TimeZone) -> Bool {
        (6..<18).contains(wallClock(at: date, in: zone).hour)
    }

    /// Formats the local time in `zone`, for example "3:42 PM" or "15:42".
    public static func timeText(at date: Date, in zone: TimeZone, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = zone
        return date.formatted(style)
    }

    private static func dayNumber(of date: Date, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}
