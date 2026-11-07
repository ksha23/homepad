import Foundation
import HomePadCore

/// Storage behind the calendar service: EventKit on a real iPad, demo data in
/// the simulator. Backends know nothing about household privacy. The service
/// filters every result through `CalendarVisibilityPolicy` before showing it.
@MainActor
protocol CalendarBackend: AnyObject {
    var hasEventAccess: Bool { get }
    var hasReminderAccess: Bool { get }
    /// True when someone declined access, so only the Settings app can grant it.
    var isEventAccessDenied: Bool { get }
    var isReminderAccessDenied: Bool { get }
    /// The exact calendar access level, for Settings and for explaining write-only access.
    var eventAccessState: CalendarAccessState { get }
    /// Shows the system permission prompt if needed. Returns the new state.
    func requestEventAccess() async -> Bool
    func requestReminderAccess() async -> Bool

    func eventCalendars() -> [CalendarSource]
    func reminderLists() -> [CalendarSource]
    /// The calendar new events land in when the caller does not choose one.
    func defaultEventCalendarID() -> String?

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [PersonalEvent]
    func reminders(listIDs: Set<String>, includeCompleted: Bool) async -> [ReminderItem]

    func addEvent(_ draft: EventDraft, calendarID: String) throws -> PersonalEvent
    func addReminder(title: String, due: Date?, listID: String) throws -> ReminderItem
    func setCompleted(reminderID: String, completed: Bool) throws
    func removeReminder(reminderID: String) throws
    func createReminderList(named name: String) throws -> CalendarSource

    /// Called whenever the underlying store changes (another device edited it).
    var onChange: (() -> Void)? { get set }

    /// Asks the accounts behind the store for changes when its copy is out of
    /// date. What changes comes back through `onChange`.
    func refreshSources()
}

extension CalendarBackend {
    /// Demo data has nothing to fetch.
    func refreshSources() {}
}
