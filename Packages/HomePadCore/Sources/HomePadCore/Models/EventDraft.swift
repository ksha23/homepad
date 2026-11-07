import Foundation

/// A new event for `CalendarService.addEvent(_:)`, from the assistant, a
/// scanned flyer or another module.
public struct EventDraft: Hashable, Sendable {
    public var title: String
    public var start: Date
    /// For an all-day event, any time on its last day.
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// Nil picks the best calendar for the current viewer.
    public var calendarID: String?

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil, calendarID: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarID = calendarID
    }
}

/// A calendar the person at the screen may add events to, as other modules see it.
public struct EventCalendarInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var colorHex: String?
    /// The account it lives in, such as "iCloud" or "Gmail".
    public var accountName: String?
    /// Shared with the whole household, rather than personal to someone.
    public var isShared: Bool

    public init(id: String, title: String, colorHex: String? = nil, accountName: String? = nil, isShared: Bool = false) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.accountName = accountName
        self.isShared = isShared
    }
}
