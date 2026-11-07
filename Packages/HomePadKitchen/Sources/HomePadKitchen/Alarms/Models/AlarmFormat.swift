import Foundation
import HomePadUI

/// Text for alarms: "7:00" and "AM" for rows, "7:00 AM" in sentences,
/// "Weekdays" for the days, "in 8 hr 12 min" for the next one.
enum AlarmFormat {
    /// Today at the alarm's time, for formatting.
    static func date(of alarm: HomeAlarm, calendar: Calendar = .current, now: Date = Date()) -> Date {
        calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: now) ?? now
    }

    /// "7:00", without AM or PM, following the locale's 12 or 24 hours.
    static func clockTime(_ alarm: HomeAlarm, locale: Locale = .current) -> String {
        date(of: alarm).clockTime(locale: locale)
    }

    /// "AM" or "PM" in 12-hour locales, nil in 24-hour ones.
    static func dayPeriod(_ alarm: HomeAlarm, locale: Locale = .current) -> String? {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        guard template.contains("a") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        return alarm.hour < 12 ? formatter.amSymbol : formatter.pmSymbol
    }

    /// "7:00 AM", for sentences and VoiceOver.
    static func time(_ alarm: HomeAlarm, locale: Locale = .current) -> String {
        [clockTime(alarm, locale: locale), dayPeriod(alarm, locale: locale)].compactMap { $0 }.joined(separator: " ")
    }

    /// "Every day", "Weekdays", "Weekends", "Mon, Wed, Fri", or "Once".
    static func repeatText(_ weekdays: Set<Locale.Weekday>, calendar: Calendar = .current) -> String {
        switch weekdays {
        case []: return "Once"
        case Set(Locale.Weekday.ordered): return "Every day"
        case Locale.Weekday.workweek: return "Weekdays"
        case Locale.Weekday.weekend: return "Weekends"
        default:
            let symbols = calendar.shortWeekdaySymbols
            return orderedForWeek(weekdays, calendar: calendar)
                .map { symbols[Locale.Weekday.ordered.firstIndex(of: $0) ?? 0] }
                .joined(separator: ", ")
        }
    }

    /// Days in the order the locale's week runs, Monday first in most of the world.
    static func orderedForWeek(_ weekdays: Set<Locale.Weekday>, calendar: Calendar = .current) -> [Locale.Weekday] {
        let first = calendar.firstWeekday - 1
        let week = Array(Locale.Weekday.ordered[first...] + Locale.Weekday.ordered[..<first])
        return week.filter { weekdays.contains($0) }
    }

    /// "Wake Up, weekdays" or "Alarm" for a row under the time.
    static func subtitle(_ alarm: HomeAlarm) -> String {
        alarm.repeats ? "\(alarm.title), \(repeatText(alarm.weekdays).lowercasedFirstWord)" : alarm.title
    }

    /// "in 8 hr 12 min", "in 2 days 3 hr" or "in 5 min", rounded up to the minute.
    static func countdown(to date: Date, from now: Date) -> String {
        let total = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let days = total / (24 * 60), hours = total % (24 * 60) / 60, minutes = total % 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 && days == 0 { parts.append("\(minutes) min") }
        return "in " + parts.joined(separator: " ")
    }

    /// "today at 7:00 AM", "tomorrow at 6:30 AM" or "Saturday at 9:00 AM".
    static func when(_ date: Date, from now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
    }
}

private extension String {
    /// "weekdays" from "Weekdays", but "Mon, Wed" stays as it is.
    var lowercasedFirstWord: String {
        guard !contains(",") else { return self }
        return prefix(1).lowercased() + dropFirst()
    }
}
