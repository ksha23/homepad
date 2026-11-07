import Foundation
import HomePadCore

// Each person's own phone calendars and reminders lists
// (`RemoteProtocol.phoneCalendars` and later), two kinds of data a phone
// visit carries (`PhoneVisitMessages.swift` has the visit's hello, challenge
// and close). Inside an open visit, on its one session:
//
//   phone   calendar.offer      which calendars and lists it shares, with its wake tag
//   HomePad calendar.request    the shared calendars and their events between two days
//   phone   calendar.reply
//   HomePad reminders.request   the shared lists, open reminders and those checked off lately
//   phone   reminders.reply
//   HomePad calendar.change     add an event, or change one occurrence
//   phone   calendar.changed    the event as saved, or why not
//   HomePad reminders.change    add a reminder, or check one off
//   phone   reminders.changed   the reminder as saved, or why not
extension PeerMessageType {
    /// What a phone shares of its calendars and lists with a HomePad (`CalendarShareOffer`).
    public static let calendarOffer = PeerMessageType("calendar.offer")
    /// The HomePad asks for the shared calendars' events (`CalendarRequest`).
    public static let calendarRequest = PeerMessageType("calendar.request")
    /// The phone's calendars and events (`CalendarReply`).
    public static let calendarReply = PeerMessageType("calendar.reply")
    /// The HomePad asks for the shared lists' reminders (`RemindersRequest`).
    public static let remindersRequest = PeerMessageType("reminders.request")
    /// The phone's lists and reminders (`RemindersReply`).
    public static let remindersReply = PeerMessageType("reminders.reply")
    /// A change to an event, to save on the phone (`CalendarChange`).
    public static let calendarChange = PeerMessageType("calendar.change")
    /// The phone saved the change, or could not (`CalendarChanged`).
    public static let calendarChanged = PeerMessageType("calendar.changed")
    /// A change to a reminder, to save on the phone (`RemindersChange`).
    public static let remindersChange = PeerMessageType("reminders.change")
    /// The phone saved the change, or could not (`RemindersChanged`).
    public static let remindersChanged = PeerMessageType("reminders.changed")
}

/// Limits of phone calendars.
enum PhoneCalendarsPolicy {
    /// Days of events before today a visit fetches.
    static let daysBefore = 7
    /// Days of events from today a visit fetches: six weeks.
    static let daysAfter = 42
    /// Most events in one answer.
    static let eventLimit = 2000
    /// Most reminders in one answer.
    static let reminderLimit = 1000
    /// Checked-off reminders this many days back still come, so a list shows what was just done.
    static let completedDays = 7
    /// How long the HomePad waits for the phone to save a change, once it is open.
    static let changeTimeout: TimeInterval = 15

    /// The days a visit asks for around `now`: the past week to six weeks ahead, whole days.
    static func window(around now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -daysBefore, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: daysAfter + 1, to: today) ?? today
        return DateInterval(start: start, end: max(end, start))
    }
}

/// Body of `calendar.offer`: the calendars and lists this phone shares with
/// the HomePad, by the phone's identifiers only, and the tag it writes over
/// Bluetooth. Empty lists mean it shares none of that kind. The HomePad
/// drops what it saved of anything no longer listed at once.
public struct CalendarShareOffer: Codable, Equatable, Sendable {
    public var calendarIDs: [String]
    public var listIDs: [String]
    public var wakeTag: Data?

    public init(calendarIDs: [String], listIDs: [String], wakeTag: Data?) {
        self.calendarIDs = calendarIDs
        self.listIDs = listIDs
        self.wakeTag = wakeTag
    }
}

/// Body of `calendar.request`.
public struct CalendarRequest: Codable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// The HomePad's changes still waiting for an answer, so the phone can
    /// say which it saved already when an answer got lost.
    public var pendingChanges: [UUID]?

    public init(id: UUID = UUID(), start: Date, end: Date, pendingChanges: [UUID]? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.pendingChanges = pendingChanges
    }
}

/// Body of `calendar.reply`.
public struct CalendarReply: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// The calendars the person shares with this HomePad, the default first.
    public var calendars: [PhoneCalendar]
    /// Their events between the request's days, each occurrence on its own.
    public var events: [PhoneEvent]
    /// Which of the request's pending changes the phone has saved, already
    /// in `events`, so the HomePad stops sending them.
    public var savedChanges: [UUID]?

    public init(requestID: UUID, calendars: [PhoneCalendar], events: [PhoneEvent], savedChanges: [UUID]? = nil) {
        self.requestID = requestID
        self.calendars = calendars
        self.events = events
        self.savedChanges = savedChanges
    }
}

/// Body of `reminders.request`.
public struct RemindersRequest: Codable, Equatable, Sendable {
    public var id: UUID
    /// Checked-off reminders from this time on come too.
    public var completedSince: Date
    /// Like `CalendarRequest.pendingChanges`.
    public var pendingChanges: [UUID]?

    public init(id: UUID = UUID(), completedSince: Date, pendingChanges: [UUID]? = nil) {
        self.id = id
        self.completedSince = completedSince
        self.pendingChanges = pendingChanges
    }
}

/// Body of `reminders.reply`.
public struct RemindersReply: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var lists: [PhoneCalendar]
    public var reminders: [PhoneReminder]
    /// Like `CalendarReply.savedChanges`.
    public var savedChanges: [UUID]?

    public init(requestID: UUID, lists: [PhoneCalendar], reminders: [PhoneReminder], savedChanges: [UUID]? = nil) {
        self.requestID = requestID
        self.lists = lists
        self.reminders = reminders
        self.savedChanges = savedChanges
    }
}

/// An event's fields, for adding one or changing one.
public struct PhoneEventFields: Codable, Equatable, Sendable {
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?

    public init(calendarID: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String?) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }

    init(_ draft: EventDraft, calendarID: String) {
        self.init(calendarID: calendarID, title: draft.title, start: draft.start, end: draft.end,
                  isAllDay: draft.isAllDay, location: draft.location)
    }
}

/// Body of `calendar.change`. Without `itemID` it adds an event. With it, it
/// changes the occurrence starting at `occurrenceStart` only.
public struct CalendarChange: Codable, Equatable, Sendable {
    /// The change's own ID. The phone saves each ID once, so a change sent
    /// again after a lost answer is never added twice.
    public var id: UUID
    public var itemID: String?
    public var occurrenceStart: Date?
    public var fields: PhoneEventFields

    public init(id: UUID = UUID(), itemID: String? = nil, occurrenceStart: Date? = nil, fields: PhoneEventFields) {
        self.id = id
        self.itemID = itemID
        self.occurrenceStart = occurrenceStart
        self.fields = fields
    }
}

/// Why a phone could not save a change.
public enum PhoneChangeFailure: String, Codable, Sendable, Error {
    /// The event or reminder is gone from the phone.
    case notFound
    /// The calendar or list is read-only on the phone.
    case readOnly
    /// The person no longer shares that calendar or list with the HomePad.
    case notShared
    /// HomePad on the phone has no full access to Calendar or Reminders.
    case noAccess
    /// The phone tried and EventKit said no.
    case saveFailed
}

/// Body of `calendar.changed`. Exactly one of `event` and `failure` is set.
public struct CalendarChanged: Codable, Equatable, Sendable {
    public var changeID: UUID
    public var event: PhoneEvent?
    /// A name, so a reason a newer phone adds still reads as a failure.
    public var failure: String?

    public init(changeID: UUID, event: PhoneEvent? = nil, failure: PhoneChangeFailure? = nil) {
        self.changeID = changeID
        self.event = event
        self.failure = failure?.rawValue
    }
}

/// A new reminder's fields.
public struct PhoneReminderFields: Codable, Equatable, Sendable {
    public var listID: String
    public var title: String
    public var due: Date?
    public var dueHasTime: Bool

    public init(listID: String, title: String, due: Date? = nil, dueHasTime: Bool = false) {
        self.listID = listID
        self.title = title
        self.due = due
        self.dueHasTime = dueHasTime
    }
}

/// Body of `reminders.change`: adds a reminder, or checks one off or back on.
public struct RemindersChange: Codable, Equatable, Sendable {
    /// Saved once by the phone, like `CalendarChange.id`.
    public var id: UUID
    public var add: PhoneReminderFields?
    public var reminderID: String?
    public var completed: Bool?

    public init(id: UUID = UUID(), add: PhoneReminderFields? = nil, reminderID: String? = nil, completed: Bool? = nil) {
        self.id = id
        self.add = add
        self.reminderID = reminderID
        self.completed = completed
    }
}

/// Body of `reminders.changed`. Exactly one of `reminder` and `failure` is set.
public struct RemindersChanged: Codable, Equatable, Sendable {
    public var changeID: UUID
    public var reminder: PhoneReminder?
    public var failure: String?

    public init(changeID: UUID, reminder: PhoneReminder? = nil, failure: PhoneChangeFailure? = nil) {
        self.changeID = changeID
        self.reminder = reminder
        self.failure = failure?.rawValue
    }
}
