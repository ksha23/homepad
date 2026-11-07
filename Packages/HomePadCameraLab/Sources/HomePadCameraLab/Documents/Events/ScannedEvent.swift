import Foundation
import HomePadCore

/// An event found on a scanned page, as the person reviews it. Every field
/// can be changed before it goes to a calendar.
struct ScannedEvent: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    /// The start, or the first day at midnight for an all-day event.
    var start: Date
    /// The end, or the last day at midnight for an all-day event.
    var end: Date
    var isAllDay: Bool
    /// Empty when the page names no place.
    var location: String
    /// Added when the person adds the selected events. A deadline, such as
    /// an RSVP date, starts unselected.
    var isSelected: Bool
    /// The words on the page it came from, so the person can check it.
    var source: String

    /// What the calendar service adds. An all-day event ends on its last day.
    func draft(calendarID: String?, calendar: Calendar = .current) -> EventDraft {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = isAllDay ? calendar.startOfDay(for: start) : start
        let last: Date
        if isAllDay {
            let lastDay = max(calendar.startOfDay(for: end), first)
            last = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: lastDay) ?? lastDay
        } else {
            last = max(end, start)
        }
        return EventDraft(title: trimmedTitle.isEmpty ? "Event" : trimmedTitle, start: first, end: last,
                          isAllDay: isAllDay, location: place.isEmpty ? nil : place, calendarID: calendarID)
    }
}
