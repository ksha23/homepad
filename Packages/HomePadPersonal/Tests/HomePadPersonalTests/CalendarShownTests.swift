import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// The Calendars list: each person (and guests) checks which calendars show,
/// the choice reaches the app, Up Next and the faces alike, and it never
/// changes who a calendar belongs to.
@MainActor
@Suite struct CalendarShownTests {
    let settings: SettingsStore
    let household: Household
    let service: HouseholdCalendarService
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
    let sam = HouseholdMember(name: "Sam")
    let work = DemoCalendarBackend.work
    let holidays = DemoCalendarBackend.holidays

    init() {
        let defaults = UserDefaults(suiteName: "homepad.personal.shown.\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults)
        settings[PersonalSettings.demoData] = true
        household = Household(store: settings)
        household.add(kyle)
        household.add(sam)
        service = HouseholdCalendarService(household: household, settings: settings)
    }

    private var week: (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: Date())
        return (start, start.addingTimeInterval(7 * 86_400))
    }

    @Test func everyVisibleCalendarStartsChecked() {
        household.recognize(kyle.id)
        #expect(service.shownCalendars == service.visibleCalendars)
    }

    @Test func uncheckingHidesEventsEverywhereButKeepsOwnership() async {
        household.recognize(kyle.id)
        service.setShown(false, for: work)
        #expect(!service.isShown(work))
        #expect(!service.shownCalendars.contains(work))
        // The app and Up Next read `agenda`, the faces read the Core protocol.
        #expect(!service.agenda(from: week.start, to: week.end).contains { $0.calendarID == work.id })
        #expect(!service.upNext().events.contains { $0.calendarID == work.id })
        let core: any CalendarService = service
        #expect(!(await core.events(from: week.start, to: week.end)).contains { $0.calendarName == work.title })
        // Who may see it is unchanged: still Kyle's, still visible, nothing saved in Settings.
        #expect(service.visibleCalendars.contains(work))
        #expect(service.status(of: work).isVisibleNow)
        #expect(settings[PersonalSettings.calendarAudiences].isEmpty)
        #expect(service.hiddenNote(.events) == nil)
    }

    @Test func eachPersonAndGuestsHaveTheirOwnChoice() {
        household.recognize(kyle.id)
        service.setShown(false, for: holidays)
        household.recognize(sam.id)
        #expect(service.isShown(holidays))
        household.signOut()
        #expect(service.isShown(holidays))
        service.setShown(false, for: DemoCalendarBackend.home)
        household.recognize(kyle.id)
        #expect(!service.isShown(holidays))
        #expect(service.isShown(DemoCalendarBackend.home))
    }

    @Test func theChoiceSurvivesARelaunch() {
        household.recognize(kyle.id)
        service.setShown(false, for: work)
        let relaunched = HouseholdCalendarService(household: household, settings: settings)
        #expect(!relaunched.isShown(work))
    }

    @Test func showAllAndHideAllTouchOnlyTheListedCalendars() {
        household.recognize(kyle.id)
        service.setShown(false, for: work)
        // Kyle picked by hand is not recognized: his personal calendars are not
        // listed, so Show All leaves Work unchecked.
        household.select(nil)
        household.select(kyle.id)
        #expect(!service.visibleCalendars.contains(work))
        service.showAll()
        household.recognize(kyle.id)
        #expect(!service.isShown(work))
        service.hideAll()
        #expect(service.shownCalendars.isEmpty)
        #expect(service.agenda(from: week.start, to: week.end).isEmpty)
        service.showAll()
        #expect(service.shownCalendars == service.visibleCalendars)
        #expect(settings[PersonalSettings.uncheckedCalendars].isEmpty)
    }

    @Test func facesReloadWhenTheChoiceChanges() {
        let core: any CalendarService = service
        let before = core.reloadKey
        service.setShown(false, for: holidays)
        #expect(core.reloadKey != before)
    }

    @Test func newEventsGoToACheckedCalendar() {
        household.recognize(kyle.id)
        #expect(service.preferredCalendarForNewEvents()?.id == DemoCalendarBackend.personal.id)
        service.setShown(false, for: DemoCalendarBackend.personal)
        service.setShown(false, for: work)
        #expect(service.preferredCalendarForNewEvents()?.id == DemoCalendarBackend.family.id)
    }

    @Test func calendarsAreGroupedByAccountLikeApple() {
        let gmail = CalendarSource(id: "g", title: "Soccer", colorHex: "#FFFFFF", kind: .events, accountName: "Gmail")
        let canvas = CalendarSource(id: "c", title: "Canvas", colorHex: "#FFFFFF", kind: .events,
                                    accountName: "Subscribed Calendars", calendarType: .subscription)
        let groups = CalendarAccountGroup.groups([holidays, canvas, work, gmail, DemoCalendarBackend.family])
        #expect(groups.map(\.title) == ["iCloud", "Gmail", "Subscribed Calendars", "Other"])
        #expect(groups.first?.calendars.map(\.title) == ["Family", "Work"])
    }
}
