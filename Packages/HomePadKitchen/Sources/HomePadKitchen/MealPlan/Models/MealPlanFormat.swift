import Foundation

/// How the meal plan names days and weeks, on screen and to the assistant.
enum MealPlanFormat {
    /// "Today", "Tomorrow", "Thursday" within the coming week, else "Thursday, November 12".
    static func dayName(_ day: MealDay, today: MealDay = .today(), calendar: Calendar = .current) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: 1, calendar: calendar) { return "Tomorrow" }
        let date = day.date(in: calendar)
        if today < day, day <= today.adding(days: 6, calendar: calendar) {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return fullDay(day, calendar: calendar)
    }

    /// "Thursday, November 12".
    static func fullDay(_ day: MealDay, calendar: Calendar = .current) -> String {
        day.date(in: calendar).formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Thu", for a day column.
    static func shortWeekday(_ day: MealDay, calendar: Calendar = .current) -> String {
        day.date(in: calendar).formatted(.dateTime.weekday(.abbreviated))
    }

    /// "12", for a day column.
    static func dayNumber(_ day: MealDay) -> String {
        String(day.day)
    }

    /// "This Week", "Next Week" or "Last Week", or nil for any other week.
    static func weekTitle(_ week: MealWeek, today: MealDay = .today(), calendar: Calendar = .current) -> String? {
        let current = MealWeek(containing: today, calendar: calendar)
        switch week {
        case current: return "This Week"
        case current.offset(by: 1, calendar: calendar): return "Next Week"
        case current.offset(by: -1, calendar: calendar): return "Last Week"
        default: return nil
        }
    }

    /// "November 2 to 8", or "October 26 to November 1" across two months.
    static func weekRange(_ week: MealWeek, calendar: Calendar = .current) -> String {
        dayRange(week.start, week.end(calendar: calendar), calendar: calendar)
    }

    /// "Thursday to Sunday" within a week, or a range of dates.
    static func days(_ range: ClosedRange<MealDay>, today: MealDay = .today(), calendar: Calendar = .current) -> String {
        if range.lowerBound == range.upperBound { return dayName(range.lowerBound, today: today, calendar: calendar) }
        let span = calendar.dateComponents([.day], from: range.lowerBound.date(in: calendar), to: range.upperBound.date(in: calendar)).day ?? 0
        guard span < 7 else { return dayRange(range.lowerBound, range.upperBound, calendar: calendar) }
        let first = range.lowerBound == today ? "Today" : range.lowerBound.date(in: calendar).formatted(.dateTime.weekday(.wide))
        return "\(first) to \(range.upperBound.date(in: calendar).formatted(.dateTime.weekday(.wide)))"
    }

    private static func dayRange(_ first: MealDay, _ last: MealDay, calendar: Calendar) -> String {
        let start = first.date(in: calendar).formatted(.dateTime.month(.wide).day())
        let end = first.month == last.month
            ? String(last.day)
            : last.date(in: calendar).formatted(.dateTime.month(.wide).day())
        return "\(start) to \(end)"
    }

    // MARK: Spoken days

    /// Reads a day the way the assistant passes one: an ISO 8601 date
    /// ("2026-11-12"), "today", "tomorrow", or a weekday ("thursday",
    /// "next friday"), which means the next one from today on.
    static func day(from spoken: String, today: MealDay = .today(), calendar: Calendar = .current) -> MealDay? {
        let text = spoken.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = MealDay(isoString: String(text.prefix(10))) { return iso }
        if text.contains("tomorrow") { return today.adding(days: 1, calendar: calendar) }
        if text == "today" || text == "tonight" { return today }
        let names = calendar.weekdaySymbols.map { $0.lowercased() }
        guard let index = names.firstIndex(where: { text.contains($0) }) else { return nil }
        let todayIndex = calendar.component(.weekday, from: today.date(in: calendar)) - 1
        var ahead = (index - todayIndex + 7) % 7
        // "Next Friday" said on a Friday means a week out, not today.
        if ahead == 0, text.hasPrefix("next") { ahead = 7 }
        return today.adding(days: ahead, calendar: calendar)
    }
}

extension MealDay: Identifiable {
    public var id: String { isoString }
}
