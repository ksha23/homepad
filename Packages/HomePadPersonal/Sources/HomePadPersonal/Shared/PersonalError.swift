import Foundation

/// Errors from the personal services, worded for people (the assistant reads them aloud).
public enum PersonalError: LocalizedError, Sendable {
    case noCalendarAccess
    case noReminderAccess
    case calendarNotFound(String)
    case reminderNotFound(String)
    case listNotFound(String)
    case notVisible
    case noWritableCalendar
    case demoDataIsReadOnly

    public var errorDescription: String? {
        switch self {
        case .noCalendarAccess: "HomePad does not have access to Calendar yet."
        case .noReminderAccess: "HomePad does not have access to Reminders yet."
        case .calendarNotFound: "That calendar is no longer available."
        case .reminderNotFound: "That reminder is no longer available."
        case .listNotFound(let name): "There is no reminders list called \(name)."
        case .notVisible: "That belongs to someone who is not recognized right now."
        case .noWritableCalendar: "There is no calendar on this HomePad that can be changed."
        case .demoDataIsReadOnly: "Demo calendars cannot be edited. Turn off demo data in Settings to use your own calendars."
        }
    }
}
