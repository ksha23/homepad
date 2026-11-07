#if DEBUG && targetEnvironment(simulator)
import CoreGraphics
import EventKit
import Foundation
import HomePadCore

/// Simulator only (`-HomePadSeedCalendars YES`): real EventKit calendars to
/// check the Calendar app and Settings without demo data. "Canvas" is shaped
/// like a school feed, with assignments due at one minute and all-day items.
/// "Family" is a calendar HomePad shares by its name.
extension EventKitCalendarBackend {
    func seedSimulatorCalendars() {
        let store = eventStore
        guard hasEventAccess,
              let account = store.sources.first(where: { $0.sourceType == .local }) ?? store.defaultCalendarForNewEvents?.source else { return }
        let existing = Set(store.calendars(for: .event).map(\.title))
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ day: Int, _ hour: Double) -> Date { today.addingTimeInterval(Double(day) * 86_400 + hour * 3600) }
        do {
            if !existing.contains("Canvas") {
                let canvas = try makeCalendar("Canvas", color: CGColor(red: 0.89, green: 0.24, blue: 0.2, alpha: 1), in: account)
                try add("Reading response [CS 639]", calendar: canvas, start: at(0, 17), end: at(0, 17))
                try add("Homework 5 [MATH 541]", calendar: canvas, start: at(0, 23 + 59.0 / 60), end: at(0, 23 + 59.0 / 60))
                try add("Quiz 3 [CS 532]", calendar: canvas, start: at(0, 0), end: at(0, 0), isAllDay: true)
                try add("Project proposal [CS 639]", calendar: canvas, start: at(2, 0), end: at(2, 0), isAllDay: true)
            }
            if !existing.contains("Family") {
                let family = try makeCalendar("Family", color: CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1), in: account)
                try add("Soccer practice", calendar: family, start: at(0, 18), end: at(0, 19.5))
            }
            try store.commit()
        } catch {
            Log.make("Calendar").error("Seeding simulator calendars failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeCalendar(_ title: String, color: CGColor, in account: EKSource) throws -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = title
        calendar.cgColor = color
        calendar.source = account
        try eventStore.saveCalendar(calendar, commit: false)
        return calendar
    }

    private func add(_ title: String, calendar: EKCalendar, start: Date, end: Date, isAllDay: Bool = false) throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: false)
    }
}
#endif
