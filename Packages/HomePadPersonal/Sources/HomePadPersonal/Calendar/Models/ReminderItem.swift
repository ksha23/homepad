import Foundation
import HomePadCore

/// One reminder with its list and completion state.
public struct ReminderItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isCompleted: Bool
    public var due: Date?
    /// False for date-only due dates ("tomorrow") so the time is not shown.
    public var dueHasTime: Bool
    public var listID: String
    public var listTitle: String
    public var colorHex: String
    /// EventKit priority: 0 none, 1 high ... 9 low.
    public var priority: Int
    public var notes: String?
    /// Set for a reminder on the recognized person's own iPhone, such as "Kyle's iPhone".
    public var phoneDeviceName: String?
    /// Set while a change made here waits for that phone, or failed.
    public var phoneStatus: PhoneWriteStatus?

    public init(
        id: String, title: String, isCompleted: Bool = false, due: Date? = nil, dueHasTime: Bool = false,
        listID: String, listTitle: String, colorHex: String, priority: Int = 0, notes: String? = nil,
        phoneDeviceName: String? = nil, phoneStatus: PhoneWriteStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.due = due
        self.dueHasTime = dueHasTime
        self.listID = listID
        self.listTitle = listTitle
        self.colorHex = colorHex
        self.priority = priority
        self.notes = notes
        self.phoneDeviceName = phoneDeviceName
        self.phoneStatus = phoneStatus
    }

    /// True when the reminder is open and its due date has passed.
    public func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let due else { return false }
        return dueHasTime ? due < now : due < calendar.startOfDay(for: now)
    }

    /// Core representation. Reminders without a due date use `distantFuture`.
    public var calendarItem: CalendarItem {
        let date = due ?? .distantFuture
        return CalendarItem(
            id: id, title: title, start: date, end: date, isAllDay: !dueHasTime,
            calendarName: listTitle, colorHex: colorHex, isReminder: true,
            isCompleted: isCompleted, listID: listID
        )
    }
}
