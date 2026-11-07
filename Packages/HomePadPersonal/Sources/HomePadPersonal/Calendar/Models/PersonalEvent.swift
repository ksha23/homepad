import Foundation
import HomePadCore

/// A calendar event with everything the Calendar app shows.
/// Converts to Core's `CalendarItem` for other modules.
public struct PersonalEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var calendarID: String
    public var calendarTitle: String
    public var colorHex: String
    public var isRecurring: Bool
    /// The same on every device for events in synced accounts, so an event
    /// on both the iPad and someone's phone shows once.
    public var externalID: String?
    /// Set for an event on the recognized person's own iPhone, such as "Kyle's iPhone".
    public var phoneDeviceName: String?
    /// Set while a change made here waits for that phone, or failed.
    public var phoneStatus: PhoneWriteStatus?

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
        location: String? = nil, notes: String? = nil, calendarID: String, calendarTitle: String,
        colorHex: String, isRecurring: Bool = false, externalID: String? = nil,
        phoneDeviceName: String? = nil, phoneStatus: PhoneWriteStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.isRecurring = isRecurring
        self.externalID = externalID
        self.phoneDeviceName = phoneDeviceName
        self.phoneStatus = phoneStatus
    }

    /// True for an event on someone's own iPhone, which changes on that phone.
    public var isOnPhone: Bool { phoneDeviceName != nil }

    /// Core representation for faces, widgets in other modules and the assistant.
    public var calendarItem: CalendarItem {
        CalendarItem(
            id: id, title: title, start: start, end: end, isAllDay: isAllDay,
            location: location, calendarName: calendarTitle, colorHex: colorHex
        )
    }

    /// True when the event touches the given day.
    public func overlaps(day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return start < dayEnd && end > dayStart || (start == end && start >= dayStart && start < dayEnd)
    }
}
