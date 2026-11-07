import Foundation

/// The hours when night mode may turn on automatically. Wraps past midnight
/// when `startMinute` is later than `endMinute` (for example 22:00 to 07:00).
struct NightSchedule: Codable, Equatable, Sendable {
    /// Minutes after midnight when night starts.
    var startMinute: Int
    /// Minutes after midnight when night ends.
    var endMinute: Int

    static let standard = NightSchedule(startMinute: 22 * 60, endMinute: 7 * 60)

    /// True when `date` falls inside the schedule. An empty schedule (start equals end) never matches.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    /// A date today at `minute` past midnight, for `DatePicker` bindings.
    static func date(forMinute minute: Int, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minute, to: midnight) ?? midnight
    }

    /// Minutes past midnight for a time picked in a `DatePicker`.
    static func minute(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
