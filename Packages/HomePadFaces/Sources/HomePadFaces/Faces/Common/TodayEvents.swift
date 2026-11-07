import Foundation
import HomePadCore
import Observation

/// Today's calendar events for a face, loaded through `services.calendar`
/// and filtered by `CalendarVisibility`.
@MainActor
@Observable
final class TodayEvents {
    private(set) var all: [CalendarItem] = []
    /// True once the first fetch has answered.
    private(set) var hasLoaded = false

    /// Reloads today's events. Faces call this from `.task` every so often
    /// and whenever `service.reloadKey` changes.
    func refresh(calendar service: any CalendarService, now: Date = Date(), calendar: Calendar = .current) async {
        defer { hasLoaded = true }
        guard service.hasAccess else {
            all = []
            return
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        all = await service.events(from: start, to: end)
    }

    /// The events a face may show. While nobody is recognized that is the
    /// shared calendars' events only.
    func visible(showPersonal: Bool) -> [CalendarItem] {
        CalendarVisibility.visible(all, showPersonal: showPersonal)
    }
}
