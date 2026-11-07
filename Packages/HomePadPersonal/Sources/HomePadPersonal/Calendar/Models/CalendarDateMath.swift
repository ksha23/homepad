import Foundation

/// Day, week or month view in the Calendar app.
public enum CalendarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case day, week, month

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// The symbol the header shows when it is short of room for the title.
    public var systemImage: String {
        switch self {
        case .day: "calendar.day.timeline.leading"
        case .week: "rectangle.split.3x1"
        case .month: "calendar"
        }
    }
}

/// Date ranges for the Calendar app's views. Pure, so tests can pin a calendar.
public enum CalendarDateMath {
    /// The seven day starts of the week containing `date`, honoring the locale's first weekday.
    public static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Whole weeks covering the month of `date` (35 or 42 days, sometimes 28).
    public static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let first = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
              let last = calendar.dateInterval(of: .weekOfYear, for: lastDay)?.end else { return [] }
        var days: [Date] = []
        var day = first
        while day < last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The span of time a view shows, used to fetch events.
    public static func interval(for mode: CalendarDisplayMode, around date: Date, calendar: Calendar = .current) -> DateInterval {
        let days: [Date]
        switch mode {
        case .day: days = [calendar.startOfDay(for: date)]
        case .week: days = week(containing: date, calendar: calendar)
        case .month: days = monthGrid(containing: date, calendar: calendar)
        }
        let start = days.first ?? calendar.startOfDay(for: date)
        let end = days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// Moves forward or back by one day, week or month.
    public static func step(_ date: Date, mode: CalendarDisplayMode, by amount: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = switch mode {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: component, value: amount, to: date) ?? date
    }
}
