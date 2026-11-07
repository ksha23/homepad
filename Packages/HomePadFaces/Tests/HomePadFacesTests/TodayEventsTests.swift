import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

/// A calendar service that returns fixed events, standing in for the Personal module.
@MainActor
private final class FakeCalendarService: CalendarService {
    var hasAccess = true
    var items: [CalendarItem] = []
    var heldBack = 0
    func requestAccess() async -> Bool { true }
    func events(from start: Date, to end: Date) async -> [CalendarItem] { items }
    func reminders(includeCompleted: Bool) async -> [CalendarItem] { [] }
    func addReminder(title: String, due: Date?, listName: String?) async throws {}
    func addEvent(title: String, start: Date, end: Date) async throws {}
    func hiddenEventCount(from start: Date, to end: Date) async -> Int { heldBack }
}

/// How faces load today's events and keep personal ones for a recognized member.
@MainActor
@Suite struct TodayEventsTests {
    let now = Date()

    @Test func lockedFacesShowSharedEventsOnly() async {
        let service = FakeCalendarService()
        service.items = [
            CalendarItem(id: "soccer", title: "Soccer", start: now, end: now.addingTimeInterval(3600), isShared: true),
            CalendarItem(id: "dentist", title: "Dentist", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(3600)),
        ]
        let events = TodayEvents()
        await events.refresh(calendar: service, now: now)
        #expect(events.visible(showPersonal: false).map(\.id) == ["soccer"])
        #expect(events.visible(showPersonal: true).map(\.id) == ["soccer", "dentist"])
    }

    /// A card's picture waits for the first answer (`faceIsLoading`), with or without access.
    @Test func loadedOnceTheFirstFetchAnswers() async {
        let service = FakeCalendarService()
        let events = TodayEvents()
        #expect(!events.hasLoaded)
        await events.refresh(calendar: service, now: now)
        #expect(events.hasLoaded)
        let withoutAccess = TodayEvents()
        service.hasAccess = false
        await withoutAccess.refresh(calendar: service, now: now)
        #expect(withoutAccess.hasLoaded)
    }

    @Test func withoutAccessNothingShows() async {
        let service = FakeCalendarService()
        service.hasAccess = false
        service.items = [CalendarItem(id: "soccer", title: "Soccer", start: now, end: now.addingTimeInterval(3600), isShared: true)]
        let events = TodayEvents()
        await events.refresh(calendar: service, now: now)
        #expect(events.all.isEmpty)
        #expect(events.visible(showPersonal: true).isEmpty)
    }

    @Test func dueDatesWithNoLengthStayUpcomingUntilTheirMinute() {
        // Canvas sends an assignment as an event that starts and ends at its due time.
        let due = now.addingTimeInterval(3600)
        let assignment = CalendarItem(id: "hw", title: "Homework 5", start: due, end: due)
        #expect(CalendarVisibility.upcoming([assignment], after: now).map(\.id) == ["hw"])
        #expect(CalendarVisibility.upcoming([assignment], after: due.addingTimeInterval(60)).isEmpty)
    }

    @Test func servicesWithoutTheNewMembersKeepWorking() async {
        // `reloadKey` and `hiddenEventCount` have defaults, so simple services need neither.
        let demo = DemoCalendarService()
        #expect(demo.reloadKey.isEmpty)
        #expect(await demo.hiddenEventCount(from: now, to: now.addingTimeInterval(86_400)) == 0)
    }
}
