import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// The Calendar app and the Up Next widget agree about a day: the widget never
/// lists an event under a day that the app's day view leaves out.
@MainActor
@Suite struct CalendarParityTests {
    let household: Household
    let service: HouseholdCalendarService
    let calendar = Calendar.current

    init() {
        let defaults = UserDefaults(suiteName: "homepad.personal.parity.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings[PersonalSettings.demoData] = true
        household = Household(store: settings)
        let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
        household.add(kyle)
        household.recognize(kyle.id)
        service = HouseholdCalendarService(household: household, settings: settings)
    }

    /// A time in the week of Monday, October 19 2026, in the test's own time zone.
    /// The demo's Monday ends at 7:15 PM and its Tuesday is the busiest day, with
    /// two all-day events and an assignment due at 11:30 PM.
    private func time(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test(arguments: [0, 1, 6, 8, 12, 18, 20, 23])
    func upNextListsOnlyWhatTheAppShowsForThatDay(hour: Int) {
        let now = time(19, hour: hour, minute: 40)
        let upNext = service.upNext(now: now, calendar: calendar)
        let appDay = Set(service.events(on: upNext.day, calendar: calendar).map(\.id))
        let extra = upNext.events.filter { !appDay.contains($0.id) }.map(\.title)
        #expect(extra.isEmpty, "Up Next lists \(extra) under \(upNext.day.formatted(date: .abbreviated, time: .omitted)), which the app does not show for that day")
    }

    @Test func upNextNamesTheDayItsEventsBelongTo() {
        let morning = service.upNext(now: time(19, hour: 1, minute: 40), calendar: calendar)
        #expect(morning.day == time(19, hour: 0))
        #expect(!morning.isTomorrow)
        #expect(morning.events.map(\.id) == service.events(on: morning.day, calendar: calendar).map(\.id))
    }

    /// The tall widget goes on into tomorrow under today's events, without listing anything twice.
    @Test func theTallWidgetGoesOnWithTomorrow() {
        let morning = service.upNext(now: time(19, hour: 6, minute: 40), calendar: calendar)
        let following = service.upNextFollowingDay(after: morning, calendar: calendar)
        let listed = Set(morning.events.map(\.id))
        let tuesday = service.events(on: time(20, hour: 0), calendar: calendar)
        #expect(!following.isEmpty)
        #expect(following.map(\.id) == tuesday.filter { !listed.contains($0.id) }.map(\.id))
        // Once Up Next has moved on to tomorrow, nothing is added under it.
        let evening = service.upNext(now: time(19, hour: 20, minute: 40), calendar: calendar)
        #expect(evening.isTomorrow)
        #expect(service.upNextFollowingDay(after: evening, calendar: calendar).isEmpty)
    }

    @Test func afterTheLastEventUpNextLooksAheadToTomorrow() {
        let evening = service.upNext(now: time(19, hour: 20, minute: 40), calendar: calendar)
        #expect(evening.isTomorrow)
        #expect(evening.day == time(20, hour: 0))
        #expect(evening.events.map(\.id) == service.events(on: time(20, hour: 0), calendar: calendar).map(\.id))
    }

    /// The widget sleeps until `nextChange`, so the list must stay the same
    /// until then and change right at it.
    @Test(arguments: [0, 6, 8, 9, 12, 18, 20, 23])
    func upNextStaysTheSameUntilItsNextChange(hour: Int) {
        let now = time(19, hour: hour, minute: 40)
        let upNext = service.upNext(now: now, calendar: calendar)
        let change = upNext.nextChange(after: now, calendar: calendar)
        #expect(change > now)
        let justBefore = service.upNext(now: change.addingTimeInterval(-1), calendar: calendar)
        #expect(justBefore == upNext)
        let atChange = service.upNext(now: change, calendar: calendar)
        #expect(atChange != upNext)
    }

    @Test func upNextChangesWhenAnEventEndsOrAtMidnight() {
        // Monday at 6:40: the run ends at 8:00.
        let morning = time(19, hour: 6, minute: 40)
        #expect(service.upNext(now: morning, calendar: calendar).nextChange(after: morning, calendar: calendar) == time(19, hour: 8))
        // Monday at 8:40, looking at tomorrow: nothing changes before midnight.
        let evening = time(19, hour: 20, minute: 40)
        #expect(service.upNext(now: evening, calendar: calendar).nextChange(after: evening, calendar: calendar) == time(20, hour: 0))
    }

    @Test func allDayEventsStayUntilTheDayEnds() {
        let late = service.upNext(now: time(20, hour: 23, minute: 45), calendar: calendar)
        #expect(!late.isTomorrow)
        #expect(late.events.count == 2)
        #expect(late.events.allSatisfy { $0.isAllDay })
    }
}
