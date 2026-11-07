import Foundation

/// The event lists the Calendar app and the Up Next widget draw. Both come from
/// `events(on:)`, so the widget never lists an event under a day that the
/// app's day view leaves out.
extension HouseholdCalendarService {
    /// Events for the span one Calendar view shows (a day, a week or a month grid).
    public func events(for mode: CalendarDisplayMode, around date: Date, calendar: Calendar = .current) -> [PersonalEvent] {
        let range = CalendarDateMath.interval(for: mode, around: date, calendar: calendar)
        return agenda(from: range.start, to: range.end)
    }

    /// One day's events, as the Calendar app's day view lists them.
    public func events(on day: Date, calendar: Calendar = .current) -> [PersonalEvent] {
        events(for: .day, around: day, calendar: calendar).filter { $0.overlaps(day: day, calendar: calendar) }
    }

    /// What the Up Next widget lists at `now`: today's all-day events and the
    /// ones that have not ended, like the faces. Once today has nothing left it
    /// shows tomorrow, under a Tomorrow label, as Apple's Up Next widget does.
    public func upNext(now: Date = Date(), calendar: Calendar = .current) -> UpNextAgenda {
        let today = calendar.startOfDay(for: now)
        let remaining = events(on: today, calendar: calendar).filter { $0.isAllDay || $0.end > now }
        guard remaining.isEmpty, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return UpNextAgenda(day: today, isTomorrow: false, events: remaining)
        }
        return UpNextAgenda(day: tomorrow, isTomorrow: true, events: events(on: tomorrow, calendar: calendar))
    }

    /// What the tall Up Next widget lists under today's events when they leave
    /// room: tomorrow's events, without those it lists already, such as a trip
    /// that spans both days. Empty once Up Next has moved on to tomorrow, so no
    /// day shows twice.
    public func upNextFollowingDay(after agenda: UpNextAgenda, calendar: Calendar = .current) -> [PersonalEvent] {
        guard !agenda.isTomorrow, let next = calendar.date(byAdding: .day, value: 1, to: agenda.day) else { return [] }
        let listed = Set(agenda.events.map(\.id))
        return events(on: next, calendar: calendar).filter { !listed.contains($0.id) }
    }
}
