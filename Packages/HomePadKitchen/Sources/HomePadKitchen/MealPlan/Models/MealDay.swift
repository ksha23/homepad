import Foundation

/// A day in the meal plan. It is kept as a year, month and day rather than a
/// moment, so a plan stays on its days if the iPad's time zone changes.
/// Saved as "2026-11-05".
public struct MealDay: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day a moment falls on.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Reads "2026-11-05".
    public init?(isoString: String) {
        let parts = isoString.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// "2026-11-05".
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight at the start of the day.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar = .current) -> MealDay {
        MealDay(calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? date(in: calendar), calendar: calendar)
    }

    public static func today(calendar: Calendar = .current) -> MealDay {
        MealDay(Date(), calendar: calendar)
    }

    public static func < (lhs: MealDay, rhs: MealDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension MealDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = MealDay(isoString: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a day: \(text)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

/// Seven days from the locale's first weekday, the way the plan shows them.
public struct MealWeek: Hashable, Sendable {
    public let start: MealDay

    public init(containing day: MealDay, calendar: Calendar = .current) {
        let date = day.date(in: calendar)
        let first = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        start = MealDay(first, calendar: calendar)
    }

    public static func current(calendar: Calendar = .current) -> MealWeek {
        MealWeek(containing: .today(calendar: calendar), calendar: calendar)
    }

    public func days(calendar: Calendar = .current) -> [MealDay] {
        (0..<7).map { start.adding(days: $0, calendar: calendar) }
    }

    public func end(calendar: Calendar = .current) -> MealDay {
        start.adding(days: 6, calendar: calendar)
    }

    public func contains(_ day: MealDay, calendar: Calendar = .current) -> Bool {
        start <= day && day <= end(calendar: calendar)
    }

    public func offset(by weeks: Int, calendar: Calendar = .current) -> MealWeek {
        MealWeek(containing: start.adding(days: 7 * weeks, calendar: calendar), calendar: calendar)
    }
}
