import Foundation
import HomePadCore
import Observation
import Testing
@testable import HomePadPersonal

/// The calendar service end to end with the household and demo data:
/// what each person sees, and which writes are refused.
@MainActor
@Suite struct CalendarServiceFilteringTests {
    let settings: SettingsStore
    let household: Household
    let service: HouseholdCalendarService
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
    let sam = HouseholdMember(name: "Sam")

    init() {
        let defaults = UserDefaults(suiteName: "homepad.personal.tests.\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults)
        settings[PersonalSettings.demoData] = true
        household = Household(store: settings)
        household.add(kyle)
        household.add(sam)
        service = HouseholdCalendarService(household: household, settings: settings)
    }

    private var visibleTitles: [String] { service.visibleCalendars.map(\.title) }

    @Test func guestSeesOnlySharedCalendars() {
        #expect(visibleTitles == ["Family", "Home", "US Holidays"])
        #expect(!service.hiddenCalendars(.events).awaitingOwner.isEmpty)
    }

    @Test func recognizedAdminAlsoSeesUnassignedCalendars() {
        household.recognize(kyle.id)
        #expect(visibleTitles == ["Family", "Home", "Personal", "Work", "US Holidays"])
        #expect(service.hiddenCalendars(.events).awaitingOwner.isEmpty)
    }

    @Test func otherMembersSeeOnlyWhatIsTheirs() {
        service.applySelection(["demo.personal"], for: .member(sam.id), kind: .events)
        household.recognize(sam.id)
        #expect(visibleTitles == ["Family", "Home", "Personal", "US Holidays"])
        household.recognize(kyle.id)
        #expect(visibleTitles == ["Family", "Home", "Personal", "Work", "US Holidays"])
    }

    @Test func pickingAMemberByHandKeepsPersonalCalendarsLocked() {
        household.select(kyle.id)
        #expect(visibleTitles == ["Family", "Home", "US Holidays"])
    }

    @Test func eventsComeOnlyFromVisibleCalendars() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(7 * 86_400)
        let shared = Set(service.visibleCalendars.map(\.id))
        #expect(service.agenda(from: start, to: end).allSatisfy { shared.contains($0.calendarID) })
        household.recognize(kyle.id)
        #expect(service.agenda(from: start, to: end).contains { $0.calendarID == "demo.work" })
    }

    @Test func remindersFollowTheSamePolicy() async throws {
        let guestLists = service.visibleReminderLists.map(\.title)
        #expect(guestLists == ["Groceries", "Errands"])
        let guestItems = await service.reminderItems()
        #expect(!guestItems.contains { $0.listTitle == "My Tasks" })
        household.recognize(kyle.id)
        let kyleItems = await service.reminderItems()
        #expect(kyleItems.contains { $0.listTitle == "My Tasks" })
    }

    @Test func guestsCanAddGroceriesButNotPersonalItems() async throws {
        try await service.addReminder(title: "Milk", due: nil, listName: nil)
        let groceries = await service.reminderItems()
        #expect(groceries.contains { $0.title == "Milk" && $0.listTitle == "Groceries" })
        await #expect(throws: PersonalError.self) {
            try await service.addReminder(title: "Secret", due: nil, listName: "My Tasks")
        }
    }

    @Test func completingAReminderInAHiddenListIsRefused() async throws {
        household.recognize(kyle.id)
        let task = try #require(await service.reminderItems().first { $0.listTitle == "My Tasks" })
        household.signOut()
        #expect(throws: PersonalError.self) { try service.setCompleted(task, true) }
    }

    @Test func guestsAreToldWhatIsHiddenAndWhy() {
        #expect(service.hiddenNote(.events) == "2 personal calendars are hidden until their owners are recognized.")
        household.recognize(kyle.id)
        #expect(service.hiddenNote(.events) == nil)
    }

    @Test func recognizedAdminsSeeTheNamesOfCalendarsHiddenInSettings() {
        service.setChoice(.hidden, for: DemoCalendarBackend.work)
        household.recognize(kyle.id)
        #expect(service.hiddenNote(.events) == "Work is hidden in Settings, under Personal Info.")
        household.recognize(sam.id)
        #expect(service.hiddenNote(.events) == "1 personal calendar is hidden until its owner is recognized. 1 calendar is hidden in Settings, under Personal Info.")
    }

    @Test func choosingInTheListOfEveryCalendarTakesEffect() {
        let work = DemoCalendarBackend.work
        #expect(service.choice(for: work) == .automatic)
        #expect(service.automaticAudience(for: work) == .members([kyle.id]))
        service.setChoice(.everyone, for: work)
        #expect(visibleTitles.contains("Work"))
        #expect(service.status(of: work) == CalendarStatus(audience: .everyone, origin: .assigned, isVisibleNow: true))
        service.setChoice(.automatic, for: work)
        #expect(!visibleTitles.contains("Work"))
        #expect(settings[PersonalSettings.calendarAudiences].isEmpty)
    }

    @Test func householdWithoutPeopleShowsEveryCalendar() {
        let defaults = UserDefaults(suiteName: "homepad.personal.tests.\(UUID().uuidString)")!
        let emptySettings = SettingsStore(defaults: defaults)
        emptySettings[PersonalSettings.demoData] = true
        let alone = HouseholdCalendarService(household: Household(store: emptySettings), settings: emptySettings)
        #expect(alone.visibleCalendars.map(\.title) == ["Family", "Home", "Personal", "Work", "US Holidays"])
        #expect(alone.hiddenNote(.events) == nil)
    }

    @Test func facesHearHowManyEventsWaitForTheirOwner() async {
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(7 * 86_400)
        let core: any CalendarService = service
        #expect(await core.hiddenEventCount(from: start, to: end) > 0)
        household.recognize(kyle.id)
        #expect(await core.hiddenEventCount(from: start, to: end) == 0)
    }

    @Test func facesReloadWhenCalendarsChange() {
        // Faces read the key through the Core protocol, so it must not fall back to the empty default.
        let core: any CalendarService = service
        let before = core.reloadKey
        #expect(!before.isEmpty)
        service.changeToken += 1
        #expect(core.reloadKey != before)
    }

    @Test func calendarListsRedrawWhenTheStoreChanges() {
        final class Flag: @unchecked Sendable { var isSet = false }
        let redrew = Flag()
        withObservationTracking {
            _ = service.allEventCalendars
        } onChange: {
            redrew.isSet = true
        }
        service.changeToken += 1
        #expect(redrew.isSet)
    }

    @Test func coreProtocolReturnsFilteredItems() async {
        let start = Calendar.current.startOfDay(for: Date())
        let items = await service.events(from: start, to: start.addingTimeInterval(7 * 86_400))
        #expect(!items.contains { $0.calendarName == "Work" })
        let reminders = await service.reminders(includeCompleted: false)
        #expect(reminders.allSatisfy { $0.isReminder })
    }
}
