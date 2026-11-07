import EventKit
import Foundation
import HomePadCore

/// Calendars and reminders from the iPad's own accounts through EventKit.
///
/// An iPad is signed in to one Apple Account, so EventKit sees that account's
/// calendars plus any calendars other family members share with it. The
/// service decides who may see each one.
@MainActor
final class EventKitCalendarBackend: CalendarBackend {
    private let store = EKEventStore()
    /// The shared store, for EventKitUI controllers.
    var eventStore: EKEventStore { store }
    private let log = Log.make("Calendar")
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    /// EventKit pulls from iCloud, Google, Exchange and subscribed calendars
    /// only when its own copy is out of date, so this is cheap when nothing changed.
    func refreshSources() {
        store.refreshSourcesIfNecessary()
    }

    // MARK: Access

    var hasEventAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var hasReminderAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    var isEventAccessDenied: Bool { Self.isDenied(EKEventStore.authorizationStatus(for: .event)) }
    var isReminderAccessDenied: Bool { Self.isDenied(EKEventStore.authorizationStatus(for: .reminder)) }

    var eventAccessState: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Write-only access counts as denied: HomePad needs to read events to show them.
    private static func isDenied(_ status: EKAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted || status == .writeOnly
    }

    func requestEventAccess() async -> Bool {
        if hasEventAccess { return true }
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            log.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func requestReminderAccess() async -> Bool {
        if hasReminderAccess { return true }
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            log.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Calendars

    func eventCalendars() -> [CalendarSource] {
        guard hasEventAccess else { return [] }
        return store.calendars(for: .event).map { source(from: $0, kind: .events) }.sorted(by: Self.byAccountThenTitle)
    }

    func reminderLists() -> [CalendarSource] {
        guard hasReminderAccess else { return [] }
        return store.calendars(for: .reminder).map { source(from: $0, kind: .reminders) }.sorted(by: Self.byAccountThenTitle)
    }

    func defaultEventCalendarID() -> String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: Events

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [PersonalEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard hasEventAccess, !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .map(event(from:))
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    func addEvent(_ draft: EventDraft, calendarID: String) throws -> PersonalEvent {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw PersonalError.calendarNotFound(calendarID) }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return self.event(from: event)
    }

    // MARK: Reminders

    func reminders(listIDs: Set<String>, includeCompleted: Bool) async -> [ReminderItem] {
        let lists = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
        guard hasReminderAccess, !lists.isEmpty else { return [] }
        let predicate = includeCompleted
            ? store.predicateForReminders(in: lists)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map(Self.item(from:))
                continuation.resume(returning: items)
            }
        }
    }

    func addReminder(title: String, due: Date?, listID: String) throws -> ReminderItem {
        guard let list = store.calendar(withIdentifier: listID) else { throw PersonalError.calendarNotFound(listID) }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        }
        try store.save(reminder, commit: true)
        return Self.item(from: reminder)
    }

    func setCompleted(reminderID: String, completed: Bool) throws {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw PersonalError.reminderNotFound(reminderID)
        }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    func removeReminder(reminderID: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw PersonalError.reminderNotFound(reminderID)
        }
        try store.remove(reminder, commit: true)
    }

    func createReminderList(named name: String) throws -> CalendarSource {
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw PersonalError.noWritableCalendar
        }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return self.source(from: list, kind: .reminders)
    }

    // MARK: Mapping

    private func source(from calendar: EKCalendar, kind: CalendarSource.Kind) -> CalendarSource {
        let subscribed = calendar.isSubscribed || calendar.type == .subscription || calendar.type == .birthday
        return CalendarSource(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: ColorHex.string(from: calendar.cgColor),
            kind: kind,
            accountName: calendar.source?.title,
            allowsModifications: calendar.allowsContentModifications,
            isSubscribed: subscribed,
            calendarType: Self.calendarType(of: calendar),
            suggestedAudience: CalendarSource.suggestedAudience(title: calendar.title, kind: kind, isSubscribed: subscribed)
        )
    }

    private static func calendarType(of calendar: EKCalendar) -> CalendarSource.CalendarType {
        switch calendar.type {
        case .local: .local
        case .exchange: .exchange
        case .subscription: .subscription
        case .birthday: .birthday
        default: calendar.isSubscribed ? .subscription : .calDAV
        }
    }

    private func event(from event: EKEvent) -> PersonalEvent {
        PersonalEvent(
            id: event.calendarItemIdentifier + "|" + String(event.startDate.timeIntervalSinceReferenceDate),
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            colorHex: ColorHex.string(from: event.calendar.cgColor),
            isRecurring: event.hasRecurrenceRules,
            externalID: event.calendarItemExternalIdentifier
        )
    }

    nonisolated private static func item(from reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled",
            isCompleted: reminder.isCompleted,
            due: components.flatMap { Calendar.current.date(from: $0) },
            dueHasTime: components?.hour != nil,
            listID: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title,
            colorHex: ColorHex.string(from: reminder.calendar.cgColor),
            priority: reminder.priority,
            notes: reminder.notes
        )
    }

    private static func byAccountThenTitle(_ a: CalendarSource, _ b: CalendarSource) -> Bool {
        ((a.accountName ?? ""), a.title.localizedLowercase) < ((b.accountName ?? ""), b.title.localizedLowercase)
    }
}
