import EventKit
import Foundation

/// What the EventKitUI controllers (event editor, calendar chooser) need.
extension EventKitCalendarBackend {
    /// The EventKit object behind an event shown in HomePad, for editing.
    /// Matches the occurrence by start time so recurring events edit the right day.
    func ekEvent(for event: PersonalEvent) -> EKEvent? {
        guard let calendar = eventStore.calendar(withIdentifier: event.calendarID) else { return nil }
        let predicate = eventStore.predicateForEvents(withStart: event.start.addingTimeInterval(-1), end: event.end.addingTimeInterval(1), calendars: [calendar])
        let identifier = event.id.components(separatedBy: "|").first
        return eventStore.events(matching: predicate).first {
            $0.calendarItemIdentifier == identifier && abs($0.startDate.timeIntervalSince(event.start)) < 1
        }
    }

    /// A new, unsaved event for the system editor, prefilled with a sensible hour.
    func draftEvent(on day: Date, calendarID: String?) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        let start = Self.suggestedStart(on: day)
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        if let calendarID, let calendar = eventStore.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        return event
    }

    /// The next whole hour today, or 9 AM on another day.
    static func suggestedStart(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            let hour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
            return hour
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
