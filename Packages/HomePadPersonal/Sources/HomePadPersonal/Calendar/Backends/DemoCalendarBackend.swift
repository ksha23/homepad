import Foundation
import HomePadCore

/// In-memory calendars and reminders for the simulator, which has no accounts.
/// Events are generated around today so every view has something to show.
/// Reminders can be added and checked off, and the changes last until relaunch.
@MainActor
final class DemoCalendarBackend: CalendarBackend {
    var onChange: (() -> Void)?
    private var reminderStore: [ReminderItem]
    private var extraLists: [CalendarSource] = []

    static let family = CalendarSource(id: "demo.family", title: "Family", colorHex: "#34C759", kind: .events, accountName: "iCloud", suggestedAudience: .everyone)
    static let home = CalendarSource(id: "demo.home", title: "Home", colorHex: "#FF9500", kind: .events, accountName: "iCloud", suggestedAudience: .everyone)
    static let personal = CalendarSource(id: "demo.personal", title: "Personal", colorHex: "#AF52DE", kind: .events, accountName: "iCloud")
    static let work = CalendarSource(id: "demo.work", title: "Work", colorHex: "#007AFF", kind: .events, accountName: "iCloud")
    static let holidays = CalendarSource(id: "demo.holidays", title: "US Holidays", colorHex: "#FF2D55", kind: .events, accountName: "Other",
                                         allowsModifications: false, isSubscribed: true, calendarType: .subscription, suggestedAudience: .everyone)

    static let groceries = CalendarSource(id: "demo.groceries", title: "Groceries", colorHex: "#30D158", kind: .reminders, accountName: "iCloud", suggestedAudience: .everyone)
    static let errands = CalendarSource(id: "demo.errands", title: "Errands", colorHex: "#BF5AF2", kind: .reminders, accountName: "iCloud", suggestedAudience: .everyone)
    static let tasks = CalendarSource(id: "demo.tasks", title: "My Tasks", colorHex: "#0A84FF", kind: .reminders, accountName: "iCloud")

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Double) -> Date { today.addingTimeInterval(Double(dayOffset) * 86_400 + hour * 3600) }
        func item(_ id: String, _ title: String, _ list: CalendarSource, due: Date? = nil, timed: Bool = false, done: Bool = false) -> ReminderItem {
            ReminderItem(id: id, title: title, isCompleted: done, due: due, dueHasTime: timed, listID: list.id, listTitle: list.title, colorHex: list.colorHex)
        }
        reminderStore = [
            item("r1", "Oat milk", Self.groceries),
            item("r2", "Bananas", Self.groceries),
            item("r3", "Coffee beans", Self.groceries),
            item("r4", "Eggs", Self.groceries, done: true),
            item("r5", "Return library books", Self.errands, due: at(1, 0)),
            item("r6", "Pick up dry cleaning", Self.errands, due: at(0, 17), timed: true),
            item("r7", "Renew passport", Self.tasks, due: at(3, 0)),
            item("r8", "Book dentist appointment", Self.tasks),
            item("r9", "Send slides to Jordan", Self.tasks, due: at(0, 15), timed: true),
        ]
    }

    var hasEventAccess: Bool { true }
    var hasReminderAccess: Bool { true }
    var isEventAccessDenied: Bool { false }
    var isReminderAccessDenied: Bool { false }
    var eventAccessState: CalendarAccessState { .fullAccess }
    func requestEventAccess() async -> Bool { true }
    func requestReminderAccess() async -> Bool { true }

    func eventCalendars() -> [CalendarSource] { [Self.family, Self.home, Self.personal, Self.work, Self.holidays] }
    func reminderLists() -> [CalendarSource] { [Self.groceries, Self.errands, Self.tasks] + extraLists }
    func defaultEventCalendarID() -> String? { Self.family.id }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [PersonalEvent] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        var result: [PersonalEvent] = []
        while day < end {
            result += Self.template(for: day, calendar: calendar)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
            .filter { calendarIDs.contains($0.calendarID) && $0.end > start && $0.start < end }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    func reminders(listIDs: Set<String>, includeCompleted: Bool) async -> [ReminderItem] {
        reminderStore.filter { listIDs.contains($0.listID) && (includeCompleted || !$0.isCompleted) }
    }

    func addEvent(_ draft: EventDraft, calendarID: String) throws -> PersonalEvent {
        throw PersonalError.demoDataIsReadOnly
    }

    func addReminder(title: String, due: Date?, listID: String) throws -> ReminderItem {
        guard let list = reminderLists().first(where: { $0.id == listID }) else { throw PersonalError.calendarNotFound(listID) }
        let item = ReminderItem(id: UUID().uuidString, title: title, due: due, dueHasTime: due != nil,
                                listID: list.id, listTitle: list.title, colorHex: list.colorHex)
        reminderStore.append(item)
        onChange?()
        return item
    }

    func setCompleted(reminderID: String, completed: Bool) throws {
        guard let index = reminderStore.firstIndex(where: { $0.id == reminderID }) else { throw PersonalError.reminderNotFound(reminderID) }
        reminderStore[index].isCompleted = completed
        onChange?()
    }

    func removeReminder(reminderID: String) throws {
        guard reminderStore.contains(where: { $0.id == reminderID }) else { throw PersonalError.reminderNotFound(reminderID) }
        reminderStore.removeAll { $0.id == reminderID }
        onChange?()
    }

    func createReminderList(named name: String) throws -> CalendarSource {
        let list = CalendarSource(id: "demo.list.\(UUID().uuidString)", title: name, colorHex: "#FF9F0A", kind: .reminders,
                                  accountName: "iCloud", suggestedAudience: CalendarSource.suggestedAudience(title: name, kind: .reminders, isSubscribed: false))
        extraLists.append(list)
        onChange?()
        return list
    }

    // MARK: Generated events

    /// The weekday whose pattern a day follows. `-HomePadDemoWeekday` turns the
    /// whole week so that today follows the weekday it names.
    private static func weekday(of day: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: day)
        guard let today = PersonalDebugLaunch.demoWeekday else { return weekday }
        let shift = today - calendar.component(.weekday, from: Date())
        return ((weekday - 1 + shift) % 7 + 7) % 7 + 1
    }

    /// A believable week: the pattern repeats by weekday.
    private static func template(for day: Date, calendar: Calendar) -> [PersonalEvent] {
        let weekday = weekday(of: day, calendar: calendar)
        let key = Int(day.timeIntervalSinceReferenceDate / 86_400)
        func event(_ title: String, _ source: CalendarSource, _ startHour: Double, _ hours: Double, location: String? = nil) -> PersonalEvent {
            PersonalEvent(id: "demo.\(key).\(title)", title: title, start: day.addingTimeInterval(startHour * 3600),
                          end: day.addingTimeInterval((startHour + hours) * 3600), location: location,
                          calendarID: source.id, calendarTitle: source.title, colorHex: source.colorHex)
        }
        func allDay(_ title: String, _ source: CalendarSource) -> PersonalEvent {
            PersonalEvent(id: "demo.\(key).\(title)", title: title, start: day, end: day.addingTimeInterval(86_400), isAllDay: true,
                          calendarID: source.id, calendarTitle: source.title, colorHex: source.colorHex)
        }
        switch weekday {
        case 1: return [event("Farmers market", family, 9, 2, location: "Capitol Square"), event("Call Grandma", family, 16, 0.5)]
        case 2: return [event("Team standup", work, 9, 0.5), event("Run 3 miles", personal, 7, 1), event("Trash night", home, 19, 0.25)]
        case 3: return [event("Team standup", work, 9, 0.5), event("Product review", work, 12, 1.5, location: "Room 4"), event("Piano lesson", family, 16.5, 1),
                        // Long titles like Canvas items: all-day quizzes and readings, and an assignment at the minute it is due.
                        allDay("Quiz - Introduction to Watercolor Painting and Color Theory", personal),
                        allDay("Reading response 7: the printing press and the spread of news", personal),
                        event("Homework 6 due: fractions, decimals and percentages review", personal, 23.5, 0)]
        case 4: return [event("Team standup", work, 9, 0.5), event("Dentist", personal, 14, 1, location: "Lakeview Dental"), event("Book club", personal, 19, 2)]
        case 5: return [event("Team standup", work, 9, 0.5), event("Run 3 miles", personal, 7, 1), event("Soccer practice", family, 17, 1.5, location: "Westside Park")]
        case 6: return [event("Team standup", work, 9, 0.5), event("Pizza night", family, 18, 2), allDay("Payday", personal)]
        default: return [allDay("Cleaning day", home), event("Dinner with friends", family, 19, 2.5, location: "Graze")]
        }
    }
}
