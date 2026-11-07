import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// Calendar and Photos tell the assistant what they show, as personal content.
@MainActor
@Suite struct PersonalScreenContextTests {
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!

    @Test func calendarSaysItsViewAndDay() {
        #expect(PersonalScreenContext.calendarSummary(CalendarFocus(mode: .day, date: day)) == "The Day view of Thursday, October 22, 2026.")
        #expect(PersonalScreenContext.calendarSummary(CalendarFocus(mode: .week, date: day)) == "The Week view, around Thursday, October 22, 2026.")
        #expect(PersonalScreenContext.calendarSummary(CalendarFocus(mode: .month, date: day)) == "The Month view of October 2026.")
        #expect(PersonalScreenContext.calendarSummary(nil) == nil)
    }

    @Test func bothAppsRegisterPersonalSummaries() {
        let registry = ModuleRegistry()
        let focus = PersonalScreenFocus()
        let owner = UUID()
        var access = PhotoAccessPolicy(ownerID: owner, viewerID: owner)
        PersonalScreenContext.register(in: registry, focus: focus) { access }
        #expect(Set(registry.screenContexts.compactMap(\.appID)) == ["calendar", "photos"])
        #expect(registry.screenContexts.allSatisfy { $0.isPersonal })
        let photos = registry.screenContexts.first { $0.appID == "photos" }
        #expect(photos?.summary() == nil)
        focus.album = PhotoAlbum(id: "trips", title: "Summer 2026", kind: .user, count: 6)
        #expect(photos?.summary() == "The album Summer 2026 is open.")
        // Another member asking never hears the name of an album from the owner's library.
        access.viewerID = UUID()
        #expect(photos?.summary() == nil)
        focus.album = PhotoAlbum(id: "family", title: "Family Shared", kind: .shared, count: 40)
        #expect(photos?.summary() == "The album Family Shared is open.")
    }
}
