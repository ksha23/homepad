import Foundation

/// A wake-up alarm: a time of day, the days it repeats, a label, and whether
/// it may be snoozed. Alarms are personal. Each belongs to one household
/// member, who sees and changes it once recognized, while it rings out loud
/// for anyone in the room.
public struct HomeAlarm: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// The household member it belongs to.
    public var ownerID: UUID
    public var hour: Int
    public var minute: Int
    /// Empty for "Alarm".
    public var label: String
    /// The days it repeats. Empty rings once and then turns off.
    public var weekdays: Set<Locale.Weekday>
    public var allowsSnooze: Bool
    public var isEnabled: Bool

    public init(id: UUID = UUID(), ownerID: UUID, hour: Int, minute: Int, label: String = "",
                weekdays: Set<Locale.Weekday> = [], allowsSnooze: Bool = true, isEnabled: Bool = true) {
        self.id = id
        self.ownerID = ownerID
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.label = label
        self.weekdays = weekdays
        self.allowsSnooze = allowsSnooze
        self.isEnabled = isEnabled
    }

    /// How long a snooze lasts, as on iPhone.
    public static let snoozeLength: TimeInterval = 9 * 60

    /// The label, or "Alarm" when it has none.
    public var title: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Alarm" : trimmed
    }

    public var repeats: Bool { !weekdays.isEmpty }

    /// The first time after `date` the alarm rings, ignoring whether it is on.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  time > date else { continue }
            if weekdays.isEmpty || weekdays.contains(Self.weekday(of: time, calendar: calendar)) { return time }
        }
        return nil
    }

    static func weekday(of date: Date, calendar: Calendar) -> Locale.Weekday {
        Locale.Weekday.ordered[(calendar.component(.weekday, from: date) - 1) % 7]
    }
}

extension Locale.Weekday {
    /// Sunday first, matching `Calendar`'s weekday numbers (1 is Sunday).
    static let ordered: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    static let workweek: Set<Locale.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Set<Locale.Weekday> = [.saturday, .sunday]
}
