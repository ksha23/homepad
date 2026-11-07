import Foundation

/// A month laid out as six weeks of seven days, starting on the locale's
/// first weekday, with the days before and after the month filled in.
struct MonthGrid: Equatable {
    struct Day: Equatable, Identifiable {
        var date: Date
        var number: Int
        var isInMonth: Bool
        var isToday: Bool
        var id: Date { date }
    }

    var month: Date
    /// Very short weekday names in display order, such as S M T W T F S.
    var weekdaySymbols: [String]
    /// Always 42 days.
    var days: [Day]

    static let weeks = 6

    static func make(for today: Date, calendar: Calendar = .current) -> MonthGrid {
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
        let month = calendar.component(.month, from: monthStart)
        let days = (0..<(weeks * 7)).map { offset -> Day in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? gridStart
            return Day(
                date: date,
                number: calendar.component(.day, from: date),
                isInMonth: calendar.component(.month, from: date) == month,
                isToday: calendar.isDate(date, inSameDayAs: today)
            )
        }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return MonthGrid(month: monthStart, weekdaySymbols: Array(symbols[first...] + symbols[..<first]), days: days)
    }
}
