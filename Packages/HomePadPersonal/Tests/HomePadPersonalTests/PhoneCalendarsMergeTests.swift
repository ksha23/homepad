import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// The recognized person's own iPhone calendars beside the iPad's: who sees
/// them, how they merge, and that changes to them go to the phone.
@MainActor
@Suite struct PhoneCalendarsMergeTests {
    let settings: SettingsStore
    let household: Household
    let phone = FakePhoneCalendarsService()
    let service: HouseholdCalendarService
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
    let sam = HouseholdMember(name: "Sam")
    let today = Calendar.current.startOfDay(for: Date())

    init() {
        let defaults = UserDefaults(suiteName: "homepad.personal.phone.tests.\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults)
        settings[PersonalSettings.demoData] = true
        household = Household(store: settings)
        household.add(kyle)
        household.add(sam)
        let phone = phone
        service = HouseholdCalendarService(household: household, settings: settings) { phone }
    }

    /// Sam's phone: Sam's Home (the default), a read-only Holidays, and Errands
    /// and a Groceries list of their own.
    private func samsPhone(revision: Int = 1) -> PhoneCalendarSnapshot {
        let start = today.addingTimeInterval(14 * 3600)
        return PhoneCalendarSnapshot(
            memberID: sam.id, deviceName: "Sam's iPhone",
            calendars: [PhoneCalendar(id: "sam.home", title: "Sam's Home", colorHex: "#0A84FF", isDefault: true),
                        PhoneCalendar(id: "sam.holidays", title: "Holidays", colorHex: "#30D158", allowsModifications: false)],
            lists: [PhoneCalendar(id: "sam.errands", title: "Sam's Errands", colorHex: "#FF9F0A"),
                    PhoneCalendar(id: "sam.groceries", title: "Groceries", colorHex: "#FF9F0A")],
            events: [PhoneEvent(id: "p1|0", itemID: "p1", externalID: "x-climb", calendarID: "sam.home", title: "Climbing",
                                start: start, end: start + 3600)],
            // Not "r1", which a demo reminder on the iPad already uses.
            reminders: [PhoneReminder(id: "sam.r1", listID: "sam.errands", title: "Return books")],
            window: DateInterval(start: today - 7 * 86_400, end: today + 43 * 86_400), fetchedAt: Date(), isConnected: true,
            revision: revision
        )
    }

    @Test func aPhonesCalendarsShowOnlyForItsOwnerWhileRecognized() async {
        phone.snapshot = samsPhone()
        let tomorrow = today + 86_400
        func shows() -> Bool {
            service.visibleCalendars.contains { $0.id == "sam.home" }
                || service.agenda(from: today, to: tomorrow).contains { $0.title == "Climbing" }
                || service.visibleReminderLists.contains { $0.phone != nil }
        }

        #expect(!shows(), "a guest sees nothing of it")
        household.select(sam.id)
        #expect(!shows(), "picking Sam by hand is not enough")
        household.recognize(kyle.id)
        #expect(!shows(), "Kyle never sees Sam's phone")

        household.recognize(sam.id)
        #expect(service.visibleCalendars.suffix(2).map(\.title) == ["Sam's Home", "Holidays"])
        #expect(service.agenda(from: today, to: tomorrow).contains { $0.title == "Climbing" && $0.phoneDeviceName == "Sam's iPhone" })
        let items = await service.events(from: today, to: tomorrow)
        #expect(items.first { $0.title == "Climbing" }?.isShared == false)
        #expect(CalendarAccountGroup.groups(service.visibleCalendars).contains { $0.title == "Sam's iPhone" })
        // Never in Settings, where an admin would see it.
        #expect(!service.allEventCalendars.contains { $0.phone != nil })
        #expect(!service.allReminderLists.contains { $0.phone != nil })

        // Views reload when the phone's copy changes.
        let key = service.reloadKey
        phone.snapshot = samsPhone(revision: 2)
        #expect(service.reloadKey != key)

        // An event on both the iPad and the phone shows once.
        let onIPad = PersonalEvent(id: "ipad", title: "Climbing", start: today + 14 * 3600, end: today + 15 * 3600,
                                   calendarID: "demo.family", calendarTitle: "Family", colorHex: "#FF0000", externalID: "x-climb")
        #expect(service.phoneEvents(from: today, to: tomorrow, calendarIDs: ["sam.home"], besides: [onIPad]).isEmpty)
        #expect(service.phoneEvents(from: today, to: tomorrow, calendarIDs: ["sam.home"], besides: []).count == 1)
    }

    @Test func newEventsAndChangesGoToThePhone() async throws {
        phone.snapshot = samsPhone()
        household.recognize(sam.id)

        // Sam has no calendar of their own on the iPad, so new events go to their phone's default.
        #expect(service.preferredCalendarForNewEvents()?.id == "sam.home")
        let writable = await service.writableEventCalendars()
        #expect(writable.first?.id == "sam.home")
        #expect(!writable.contains { $0.id == "sam.holidays" })
        let start = today + 86_400 + 10 * 3600
        try await service.addEvent(EventDraft(title: "Haircut", start: start, end: start + 1800))
        #expect(phone.addedEvents.map(\.title) == ["Haircut"])
        #expect(phone.addedEvents.first?.calendarID == "sam.home")

        let climbing = try #require(service.agenda(from: today, to: today + 86_400).first { $0.title == "Climbing" })
        try service.updatePhoneEvent(climbing, with: EventDraft(title: "Climbing gym", start: climbing.start, end: climbing.end))
        #expect(phone.updatedEvents.map(\.0) == ["p1|0"])

        // Reminders join the lists, and checking one off or adding goes to the phone.
        let reminder = try #require(await service.reminderItems().first { $0.title == "Return books" })
        #expect(reminder.phoneDeviceName == "Sam's iPhone")
        try service.setCompleted(reminder, true)
        try service.addReminder(title: "Stamps", toListID: "sam.errands")
        try await service.addReminder(title: "Bike lock", due: nil, listName: "Sam's Errands")
        #expect(phone.completed.map(\.0) == ["sam.r1"])
        #expect(phone.addedReminders.map(\.title) == ["Stamps", "Bike lock"])

        // The household's Groceries stays the iPad's, even though Sam's phone has one too.
        #expect(service.defaultList?.phone == nil)
        try await service.addReminder(title: "Milk", due: nil, listName: nil)
        #expect(!phone.addedReminders.contains { $0.title == "Milk" })
        await #expect(throws: (any Error).self) { try await service.removeReminder(id: "sam.r1") }
    }

    @Test func changesWaitingForThePhoneSaySo() throws {
        var snapshot = samsPhone()
        let writeID = UUID()
        snapshot.events[0].status = PhoneWriteStatus(writeID: writeID, state: .waiting, message: "Sam's iPhone isn't reachable.")
        phone.snapshot = snapshot
        household.recognize(sam.id)
        let event = try #require(service.agenda(from: today, to: today + 86_400).first { $0.title == "Climbing" })
        #expect(event.phoneStatus?.state == .waiting)
        service.retryPhoneChange(writeID)
        service.discardPhoneChange(writeID)
        #expect(phone.retried == [writeID])
        #expect(phone.discarded == [writeID])

        // Nobody else can send or drop Sam's changes.
        household.recognize(kyle.id)
        service.retryPhoneChange(writeID)
        #expect(phone.retried == [writeID])
        #expect(throws: PersonalError.self) { try service.updatePhoneEvent(event, with: EventDraft(title: "x", start: Date(), end: Date())) }
    }
}

/// A phone service in memory, recording what was sent to the phone.
@MainActor
final class FakePhoneCalendarsService: PhoneCalendarsService {
    var snapshot: PhoneCalendarSnapshot?
    private(set) var addedEvents: [EventDraft] = []
    private(set) var updatedEvents: [(String, EventDraft)] = []
    private(set) var addedReminders: [(title: String, listID: String)] = []
    private(set) var completed: [(String, Bool)] = []
    private(set) var retried: [UUID] = []
    private(set) var discarded: [UUID] = []

    func addEvent(_ draft: EventDraft) throws { addedEvents.append(draft) }
    func updateEvent(_ eventID: PhoneEvent.ID, with draft: EventDraft) throws { updatedEvents.append((eventID, draft)) }
    func addReminder(title: String, due: Date?, listID: String) throws { addedReminders.append((title, listID)) }
    func setReminderCompleted(_ reminderID: PhoneReminder.ID, completed: Bool) throws { self.completed.append((reminderID, completed)) }
    func retry(_ writeID: UUID) { retried.append(writeID) }
    func discard(_ writeID: UUID) { discarded.append(writeID) }
}
