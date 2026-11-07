#if DEBUG
import Foundation
import HomePadCore

/// Made-up calendars and lists for the simulator, whose Calendar is empty
/// (`-ConnectPhoneCalendarsDemo YES` on the iPhone). Changes are kept in
/// memory, with the same rules as EventKit's store. Debug builds only.
@MainActor
final class DemoPhoneCalendars: PhoneCalendarStore {
    var onChange: (() -> Void)?
    private var savedEvents: [PhoneEvent]
    private var savedReminders: [PhoneReminder]
    private let ownCalendars = [
        PhoneCalendar(id: "demo.phone.personal", title: "Personal", colorHex: "#0A84FF", accountName: "iCloud", isDefault: true),
        PhoneCalendar(id: "demo.phone.climbing", title: "Climbing Club", colorHex: "#30D158", accountName: "iCloud"),
        PhoneCalendar(id: "demo.phone.work", title: "Work", colorHex: "#FF9F0A", accountName: "Exchange"),
    ]
    private let ownLists = [
        PhoneCalendar(id: "demo.phone.errands", title: "Errands", colorHex: "#FF9F0A", accountName: "iCloud", isDefault: true),
        PhoneCalendar(id: "demo.phone.reading", title: "Reading", colorHex: "#BF5AF2", accountName: "iCloud"),
    ]

    init(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        func event(_ id: String, _ title: String, _ calendarID: String, _ start: Date, _ end: Date,
                   allDay: Bool = false, place: String? = nil) -> PhoneEvent {
            PhoneEvent(id: "\(id)|\(start.timeIntervalSinceReferenceDate)", itemID: id, calendarID: calendarID, title: title,
                       start: start, end: end, isAllDay: allDay, location: place)
        }
        savedEvents = [
            event("demo.e1", "Dentist", "demo.phone.personal", at(0, 15), at(0, 15, 45), place: "Lakeview Dental"),
            event("demo.e2", "Bouldering", "demo.phone.climbing", at(0, 18, 30), at(0, 20), place: "Boulders Climbing Gym"),
            event("demo.e3", "Design review", "demo.phone.work", at(1, 10), at(1, 11)),
            event("demo.e4", "Lunch with Priya", "demo.phone.personal", at(1, 12), at(1, 13), place: "Graze"),
            event("demo.e5", "Mom's birthday", "demo.phone.personal", at(3, 0), at(4, 0), allDay: true),
            event("demo.e6", "Climbing trip", "demo.phone.climbing", at(9, 0), at(11, 0), allDay: true),
        ]
        savedReminders = [
            PhoneReminder(id: "demo.r1", listID: "demo.phone.errands", title: "Return library books", due: at(0, 17), dueHasTime: true),
            PhoneReminder(id: "demo.r2", listID: "demo.phone.errands", title: "Pick up dry cleaning"),
            PhoneReminder(id: "demo.r3", listID: "demo.phone.reading", title: "Finish The Overstory"),
        ]
    }

    var hasEventAccess: Bool { true }
    var hasReminderAccess: Bool { true }
    var isEventAccessDenied: Bool { false }
    var isReminderAccessDenied: Bool { false }
    func requestEventAccess() async -> Bool { true }
    func requestReminderAccess() async -> Bool { true }

    func calendars() -> [PhoneCalendar] { ownCalendars }
    func lists() -> [PhoneCalendar] { ownLists }

    func events(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [PhoneEvent] {
        savedEvents.filter { calendarIDs.contains($0.calendarID) && $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
    }

    func reminders(in listIDs: Set<String>, completedSince: Date) async -> [PhoneReminder] {
        savedReminders.filter { listIDs.contains($0.listID) }
    }

    func event(itemID: String, start: Date) -> PhoneEvent? {
        savedEvents.first { $0.itemID == itemID && abs($0.start.timeIntervalSince(start)) < 1 }
    }

    func reminder(_ reminderID: String) -> PhoneReminder? {
        savedReminders.first { $0.id == reminderID }
    }

    func addEvent(_ fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent {
        guard allowed.contains(fields.calendarID) else { throw PhoneChangeFailure.notShared }
        let itemID = "demo.added.\(UUID().uuidString)"
        let event = PhoneEvent(id: "\(itemID)|\(fields.start.timeIntervalSinceReferenceDate)", itemID: itemID,
                               calendarID: fields.calendarID, title: fields.title, start: fields.start, end: fields.end,
                               isAllDay: fields.isAllDay, location: fields.location)
        savedEvents.append(event)
        return event
    }

    func updateEvent(itemID: String, occurrenceStart: Date, with fields: PhoneEventFields, allowed: Set<String>) throws -> PhoneEvent {
        guard let at = savedEvents.firstIndex(where: { $0.itemID == itemID && abs($0.start.timeIntervalSince(occurrenceStart)) < 1 }) else {
            throw PhoneChangeFailure.notFound
        }
        guard allowed.contains(savedEvents[at].calendarID), allowed.contains(fields.calendarID) else { throw PhoneChangeFailure.notShared }
        var event = savedEvents[at]
        event.calendarID = fields.calendarID
        event.title = fields.title
        event.start = fields.start
        event.end = fields.end
        event.isAllDay = fields.isAllDay
        event.location = fields.location
        event.id = "\(itemID)|\(fields.start.timeIntervalSinceReferenceDate)"
        savedEvents[at] = event
        return event
    }

    func addReminder(_ fields: PhoneReminderFields, allowed: Set<String>) throws -> PhoneReminder {
        guard allowed.contains(fields.listID) else { throw PhoneChangeFailure.notShared }
        let reminder = PhoneReminder(id: "demo.added.\(UUID().uuidString)", listID: fields.listID, title: fields.title,
                                     due: fields.due, dueHasTime: fields.dueHasTime)
        savedReminders.append(reminder)
        return reminder
    }

    func setCompleted(_ reminderID: String, completed: Bool, allowed: Set<String>) throws -> PhoneReminder {
        guard let at = savedReminders.firstIndex(where: { $0.id == reminderID }) else { throw PhoneChangeFailure.notFound }
        guard allowed.contains(savedReminders[at].listID) else { throw PhoneChangeFailure.notShared }
        savedReminders[at].isCompleted = completed
        return savedReminders[at]
    }
}
#endif
