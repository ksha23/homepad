import CoreGraphics
import EventKit
import Foundation
import HomePadCore

/// On a phone: its owner's calendars and reminders, read and written for a
/// HomePad. EventKit on a device, made-up calendars in the simulator.
///
/// Every write names the calendars or lists the person shares with the
/// HomePad that asked, and is refused (`PhoneChangeFailure.notShared`) for
/// anything outside them, so a HomePad never changes a calendar it cannot see.
@MainActor
protocol PhoneCalendarStore: AnyObject {
    var hasEventAccess: Bool { get }
    var hasReminderAccess: Bool { get }
    /// True when the person declined, so only the Settings app can grant it.
    var isEventAccessDenied: Bool { get }
    var isReminderAccessDenied: Bool { get }
    /// Asks for full access. Call only after the person tapped something that explains why.
    func requestEventAccess() async -> Bool
    func requestReminderAccess() async -> Bool

    /// Every event calendar on the phone, the default first.
    func calendars() -> [PhoneCalendar]
    /// Every reminders list on the phone.
    func lists() -> [PhoneCalendar]
    /// Each occurrence between two dates in these calendars, by start.
    func events(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [PhoneEvent]
    /// Open reminders of these lists, and those checked off since `completedSince`.
    func reminders(in listIDs: Set<String>, completedSince: Date) async -> [PhoneReminder]

    func addEvent(_ fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent
    /// Changes one occurrence only, the one starting at `occurrenceStart`.
    func updateEvent(itemID: String, occurrenceStart: Date, with fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent
    /// The occurrence as it is now, for a change sent again after its answer was lost.
    func event(itemID: String, start: Date) -> PhoneEvent?
    func addReminder(_ fields: PhoneReminderFields, allowed: Set<String>) throws -> PhoneReminder
    func setCompleted(_ reminderID: String, completed: Bool, allowed: Set<String>) throws -> PhoneReminder
    func reminder(_ reminderID: String) -> PhoneReminder?

    /// Called when the calendars change on the phone or another device.
    var onChange: (() -> Void)? { get set }
}

/// EventKit, with full access to events and reminders, asked for separately.
@MainActor
final class EventKitPhoneCalendars: PhoneCalendarStore {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    // MARK: Access

    var hasEventAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var hasReminderAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    var isEventAccessDenied: Bool { Self.isDenied(EKEventStore.authorizationStatus(for: .event)) }
    var isReminderAccessDenied: Bool { Self.isDenied(EKEventStore.authorizationStatus(for: .reminder)) }

    /// Write-only access counts as denied: the HomePad needs to read events to show them.
    private static func isDenied(_ status: EKAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted || status == .writeOnly
    }

    func requestEventAccess() async -> Bool {
        if hasEventAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func requestReminderAccess() async -> Bool {
        if hasReminderAccess { return true }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: Reading

    func calendars() -> [PhoneCalendar] {
        guard hasEventAccess else { return [] }
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .map { Self.calendar($0, isDefault: $0.calendarIdentifier == defaultID) }
            .sorted { ($0.isDefault ? 0 : 1, $0.accountName ?? "", $0.title.localizedLowercase) < ($1.isDefault ? 0 : 1, $1.accountName ?? "", $1.title.localizedLowercase) }
    }

    func lists() -> [PhoneCalendar] {
        guard hasReminderAccess else { return [] }
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder)
            .map { Self.calendar($0, isDefault: $0.calendarIdentifier == defaultID) }
            .sorted { $0.title.localizedLowercase < $1.title.localizedLowercase }
    }

    func events(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [PhoneEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard hasEventAccess, !calendars.isEmpty, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map(Self.event).sorted { $0.start < $1.start }
    }

    func reminders(in listIDs: Set<String>, completedSince: Date) async -> [PhoneReminder] {
        let lists = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
        guard hasReminderAccess, !lists.isEmpty else { return [] }
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: completedSince, ending: nil, calendars: lists)
        return await fetch(open) + fetch(done)
    }

    private func fetch(_ predicate: NSPredicate) async -> [PhoneReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.reminder))
            }
        }
    }

    func event(itemID: String, start: Date) -> PhoneEvent? {
        occurrence(itemID: itemID, start: start).map(Self.event)
    }

    func reminder(_ reminderID: String) -> PhoneReminder? {
        (store.calendarItem(withIdentifier: reminderID) as? EKReminder).map(Self.reminder)
    }

    // MARK: Writing

    func addEvent(_ fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent {
        guard hasEventAccess else { throw PhoneChangeFailure.noAccess }
        let calendar = try writableCalendar(fields.calendarID, allowed: allowed)
        let event = EKEvent(eventStore: store)
        Self.apply(fields, to: event, calendar: calendar)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw PhoneChangeFailure.saveFailed
        }
        return Self.event(event)
    }

    func updateEvent(itemID: String, occurrenceStart: Date, with fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent {
        guard hasEventAccess else { throw PhoneChangeFailure.noAccess }
        guard let event = occurrence(itemID: itemID, start: occurrenceStart) else { throw PhoneChangeFailure.notFound }
        // The event's own calendar must be shared too, not only the one it moves to.
        guard allowed.contains(event.calendar.calendarIdentifier) else { throw PhoneChangeFailure.notShared }
        guard event.calendar.allowsContentModifications else { throw PhoneChangeFailure.readOnly }
        let calendar = try writableCalendar(fields.calendarID, allowed: allowed)
        Self.apply(fields, to: event, calendar: calendar)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw PhoneChangeFailure.saveFailed
        }
        return Self.event(event)
    }

    func addReminder(_ fields: PhoneReminderFields, allowed: Set<String>) throws -> PhoneReminder {
        guard hasReminderAccess else { throw PhoneChangeFailure.noAccess }
        guard allowed.contains(fields.listID) else { throw PhoneChangeFailure.notShared }
        guard let list = store.calendar(withIdentifier: fields.listID) else { throw PhoneChangeFailure.notFound }
        guard list.allowsContentModifications else { throw PhoneChangeFailure.readOnly }
        let reminder = EKReminder(eventStore: store)
        reminder.title = fields.title
        reminder.calendar = list
        if let due = fields.due {
            let parts: Set<Calendar.Component> = fields.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw PhoneChangeFailure.saveFailed
        }
        return Self.reminder(reminder)
    }

    func setCompleted(_ reminderID: String, completed: Bool, allowed: Set<String>) throws -> PhoneReminder {
        guard hasReminderAccess else { throw PhoneChangeFailure.noAccess }
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { throw PhoneChangeFailure.notFound }
        guard allowed.contains(reminder.calendar.calendarIdentifier) else { throw PhoneChangeFailure.notShared }
        guard reminder.calendar.allowsContentModifications else { throw PhoneChangeFailure.readOnly }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw PhoneChangeFailure.saveFailed
        }
        return Self.reminder(reminder)
    }

    // MARK: Plumbing

    private func writableCalendar(_ id: String, allowed: Set<String>) throws -> EKCalendar {
        guard allowed.contains(id) else { throw PhoneChangeFailure.notShared }
        guard let calendar = store.calendar(withIdentifier: id) else { throw PhoneChangeFailure.notFound }
        guard calendar.allowsContentModifications else { throw PhoneChangeFailure.readOnly }
        return calendar
    }

    /// The occurrence of an event that starts at `start`, so a change to a
    /// repeating event touches that day only.
    private func occurrence(itemID: String, start: Date) -> EKEvent? {
        guard let master = store.calendarItem(withIdentifier: itemID) as? EKEvent else { return nil }
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-1), end: start.addingTimeInterval(86_400),
                                                 calendars: [master.calendar])
        return store.events(matching: predicate).first {
            $0.calendarItemIdentifier == itemID && abs($0.startDate.timeIntervalSince(start)) < 1
        }
    }

    private static func apply(_ fields: PhoneEventFields, to event: EKEvent, calendar: EKCalendar) {
        event.title = fields.title
        event.startDate = fields.start
        event.endDate = fields.end
        event.isAllDay = fields.isAllDay
        event.location = fields.location
        event.calendar = calendar
    }

    private static func calendar(_ calendar: EKCalendar, isDefault: Bool) -> PhoneCalendar {
        PhoneCalendar(id: calendar.calendarIdentifier, title: calendar.title, colorHex: hex(calendar.cgColor),
                      accountName: calendar.source?.title, allowsModifications: calendar.allowsContentModifications,
                      isDefault: isDefault)
    }

    /// Notes stay on the phone: the HomePad shows titles, places and times.
    private static func event(_ event: EKEvent) -> PhoneEvent {
        PhoneEvent(id: event.calendarItemIdentifier + "|" + String(event.startDate.timeIntervalSinceReferenceDate),
                   itemID: event.calendarItemIdentifier, externalID: event.calendarItemExternalIdentifier,
                   calendarID: event.calendar.calendarIdentifier, title: event.title ?? "Untitled",
                   start: event.startDate, end: event.endDate, isAllDay: event.isAllDay, location: event.location,
                   isRecurring: event.hasRecurrenceRules)
    }

    nonisolated private static func reminder(_ reminder: EKReminder) -> PhoneReminder {
        let components = reminder.dueDateComponents
        return PhoneReminder(id: reminder.calendarItemIdentifier, listID: reminder.calendar.calendarIdentifier,
                             title: reminder.title ?? "Untitled", isCompleted: reminder.isCompleted,
                             due: components.flatMap { Calendar.current.date(from: $0) }, dueHasTime: components?.hour != nil,
                             priority: reminder.priority)
    }

    /// "#RRGGBB" in sRGB, as the iPad's own calendars carry their colors.
    private static func hex(_ color: CGColor?) -> String {
        guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return "#8E8E93" }
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(parts[0]), channel(parts[1]), channel(parts[2]))
    }
}
