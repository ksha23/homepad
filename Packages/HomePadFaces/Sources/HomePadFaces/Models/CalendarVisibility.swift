import Foundation
import HomePadCore

/// Decides which calendar events a face may show. Personal events need a
/// recognized member. Events from calendars shared with the whole household
/// (`CalendarItem.isShared`, assigned in Settings > Personal Info) always show.
enum CalendarVisibility {
    /// Events to show, in start order. All-day events first.
    static func visible(_ events: [CalendarItem], showPersonal: Bool) -> [CalendarItem] {
        events
            .filter { !$0.isReminder }
            .filter { showPersonal || $0.isShared }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// Timed events that have not ended yet, soonest first.
    static func upcoming(_ events: [CalendarItem], after now: Date) -> [CalendarItem] {
        events.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
    }
}
