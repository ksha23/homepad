import Foundation

/// The recognized person's own iPhone calendars and reminders lists, the ones
/// they chose on that iPhone to share with this HomePad. They are read on the
/// phone and sent over the local peer link. The Connect module installs the
/// real service, and the Personal module's calendar service shows them beside
/// the iPad's own calendars, so Calendar, Up Next, the glance, the faces and
/// the assistant all include them.
///
/// `snapshot` is nil unless a member is recognized here (not just picked in
/// People) and one of their linked phones shares calendars or lists. It shows
/// what the HomePad saved from the phone at once, before the phone answers, and
/// goes back to nil the moment the person stops being recognized.
///
/// Writes go to the phone. Each returns at once and shows in `snapshot` as
/// pending until the phone saved it, or as waiting or failed with the reason.
@MainActor
public protocol PhoneCalendarsService: AnyObject {
    /// The calendars and lists of the person at the HomePad, or nil.
    var snapshot: PhoneCalendarSnapshot? { get }

    /// Adds an event to one of the phone's calendars, named by `draft.calendarID`.
    func addEvent(_ draft: EventDraft) throws
    /// Changes one occurrence of an event on the phone, or an event still waiting to be added.
    func updateEvent(_ eventID: PhoneEvent.ID, with draft: EventDraft) throws
    /// Adds a reminder to one of the phone's lists.
    func addReminder(title: String, due: Date?, listID: String) throws
    /// Checks a reminder on the phone off, or back on.
    func setReminderCompleted(_ reminderID: PhoneReminder.ID, completed: Bool) throws
    /// Sends a waiting or failed change to the phone again, now.
    func retry(_ writeID: UUID)
    /// Drops a waiting or failed change, so the phone never gets it.
    func discard(_ writeID: UUID)
}

/// What one HomePad shows of a person's phone calendars and lists.
public struct PhoneCalendarSnapshot: Equatable, Sendable {
    /// Whose phone it is. Always the member recognized at the HomePad.
    public var memberID: UUID
    /// The phone's name, such as "Kyle's iPhone".
    public var deviceName: String
    /// The event calendars the person shares, the phone's default first.
    public var calendars: [PhoneCalendar]
    /// The reminders lists the person shares.
    public var lists: [PhoneCalendar]
    /// Events of the shared calendars inside `window`, with changes the
    /// HomePad made on top, marked with their state.
    public var events: [PhoneEvent]
    /// Open reminders of the shared lists, and those checked off lately.
    public var reminders: [PhoneReminder]
    /// The days the phone sent events for. Outside it the phone's calendars show nothing.
    public var window: DateInterval?
    /// When the phone last sent its calendars, nil before it ever did.
    public var fetchedAt: Date?
    /// True while the phone answers right now.
    public var isConnected: Bool
    /// Goes up with every change, so views that keep events reload.
    public var revision: Int

    public init(memberID: UUID, deviceName: String, calendars: [PhoneCalendar] = [], lists: [PhoneCalendar] = [],
                events: [PhoneEvent] = [], reminders: [PhoneReminder] = [], window: DateInterval? = nil,
                fetchedAt: Date? = nil, isConnected: Bool = false, revision: Int = 0) {
        self.memberID = memberID
        self.deviceName = deviceName
        self.calendars = calendars
        self.lists = lists
        self.events = events
        self.reminders = reminders
        self.window = window
        self.fetchedAt = fetchedAt
        self.isConnected = isConnected
        self.revision = revision
    }
}

/// A calendar or reminders list on a person's phone.
public struct PhoneCalendar: Identifiable, Hashable, Codable, Sendable {
    /// The phone's own identifier for it.
    public var id: String
    public var title: String
    /// "#RRGGBB".
    public var colorHex: String
    /// The account it lives in on the phone, such as "iCloud".
    public var accountName: String?
    /// False for subscribed and read-only calendars.
    public var allowsModifications: Bool
    /// The phone's default calendar for new events.
    public var isDefault: Bool

    public init(id: String, title: String, colorHex: String, accountName: String? = nil,
                allowsModifications: Bool = true, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.accountName = accountName
        self.allowsModifications = allowsModifications
        self.isDefault = isDefault
    }
}

/// One occurrence of an event on a person's phone.
public struct PhoneEvent: Identifiable, Hashable, Codable, Sendable {
    /// The occurrence: the event's identifier and its start.
    public var id: String
    /// The event's identifier on the phone, the same for every occurrence.
    public var itemID: String
    /// The same on every device for events in iCloud and other synced
    /// accounts, so an event the iPad also has shows once.
    public var externalID: String?
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var isRecurring: Bool
    /// Set while a change made on the HomePad waits for the phone, or failed.
    public var status: PhoneWriteStatus?

    public init(id: String, itemID: String, externalID: String? = nil, calendarID: String, title: String,
                start: Date, end: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil,
                isRecurring: Bool = false, status: PhoneWriteStatus? = nil) {
        self.id = id
        self.itemID = itemID
        self.externalID = externalID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.isRecurring = isRecurring
        self.status = status
    }
}

/// One reminder on a person's phone.
public struct PhoneReminder: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var listID: String
    public var title: String
    public var isCompleted: Bool
    public var due: Date?
    /// False for a due day without a time.
    public var dueHasTime: Bool
    /// 0 none, 1 high to 9 low, as in EventKit.
    public var priority: Int
    public var notes: String?
    /// Set while a change made on the HomePad waits for the phone, or failed.
    public var status: PhoneWriteStatus?

    public init(id: String, listID: String, title: String, isCompleted: Bool = false, due: Date? = nil,
                dueHasTime: Bool = false, priority: Int = 0, notes: String? = nil, status: PhoneWriteStatus? = nil) {
        self.id = id
        self.listID = listID
        self.title = title
        self.isCompleted = isCompleted
        self.due = due
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.notes = notes
        self.status = status
    }
}

/// Where a change made on the HomePad stands until the phone saved it.
public struct PhoneWriteStatus: Hashable, Codable, Sendable {
    public enum State: String, Hashable, Codable, Sendable {
        /// Going to the phone now, waking it if needed.
        case sending
        /// The phone could not be reached or did not answer. HomePad sends it
        /// again when the phone is back, or on Retry.
        case waiting
        /// The phone answered that it could not save it, so it is not sent again by itself.
        case failed
    }

    /// The change, for Retry and Discard.
    public var writeID: UUID
    public var state: State
    /// What happened, in words, such as "Kyle's iPhone isn't reachable."
    public var message: String?

    public init(writeID: UUID, state: State, message: String? = nil) {
        self.writeID = writeID
        self.state = state
        self.message = message
    }
}

/// Used until a module installs a real service: nobody's phone calendars show.
@MainActor
public final class NoPhoneCalendars: PhoneCalendarsService {
    public init() {}

    public var snapshot: PhoneCalendarSnapshot? { nil }
    public func addEvent(_ draft: EventDraft) throws { throw UnsupportedOperation("Adding to a phone's calendar") }
    public func updateEvent(_ eventID: PhoneEvent.ID, with draft: EventDraft) throws { throw UnsupportedOperation("Changing a phone's event") }
    public func addReminder(title: String, due: Date?, listID: String) throws { throw UnsupportedOperation("Adding to a phone's list") }
    public func setReminderCompleted(_ reminderID: PhoneReminder.ID, completed: Bool) throws {
        throw UnsupportedOperation("Checking off a phone's reminder")
    }
    public func retry(_ writeID: UUID) {}
    public func discard(_ writeID: UUID) {}
}
