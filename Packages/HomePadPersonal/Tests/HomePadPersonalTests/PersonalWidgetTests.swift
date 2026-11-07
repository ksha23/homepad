import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// The Up Next and Reminders widgets: how Up Next fills a tall tile, and which
/// list a Reminders widget shows for whoever is at the screen.
@MainActor
@Suite struct PersonalWidgetTests {
    let household: Household
    let service: HouseholdCalendarService
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
    let sam = HouseholdMember(name: "Sam")

    init() {
        let defaults = UserDefaults(suiteName: "homepad.personal.widgets.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings[PersonalSettings.demoData] = true
        household = Household(store: settings)
        household.add(kyle)
        household.add(sam)
        service = HouseholdCalendarService(household: household, settings: settings)
    }

    // MARK: Up Next

    /// The tall tile tries every event of the day with tomorrow's under it
    /// first, then fewer of the day's, and every choice has its own ID.
    @Test func upNextTriesTomorrowFirstOnTheTallSize() {
        let fits = UpNextWidgetView.fits(events: 3, nextDay: 2, most: 12)
        #expect(fits.map(\.later) == [2, 1, 0, 0, 0, 0, 0])
        #expect(fits.map(\.count) == [3, 3, 3, 2, 1, 1, 1])
        #expect(fits.last?.titleLines == 1)
        #expect(Set(fits).count == fits.count)
        // Without tomorrow's events (other sizes) it lists the day alone.
        #expect(UpNextWidgetView.fits(events: 2, nextDay: 0, most: 8).allSatisfy { $0.later == 0 })
        // A day with more events than fit never adds tomorrow.
        #expect(UpNextWidgetView.fits(events: 14, nextDay: 3, most: 12).first == UpNextWidgetView.Fit(count: 12))
    }

    // MARK: Reminders

    static let list = RemindersWidgetSettings.list

    private func shownList(_ settings: WidgetSettings) -> CalendarSource? {
        RemindersWidgetSettings.shownList(settings[Self.list], visible: service.visibleReminderLists,
                                          defaultList: service.defaultList)
    }

    @Test func aWidgetWithNoListChosenShowsTheDefaultList() {
        household.recognize(kyle.id)
        #expect(shownList(WidgetSettings())?.title == "Groceries")
    }

    @Test func aChosenListShowsWhileItsOwnerIsRecognized() {
        household.recognize(kyle.id)
        var settings = WidgetSettings()
        settings[Self.list] = "demo.errands"
        #expect(shownList(settings)?.title == "Errands")
    }

    /// My Tasks belongs to the admins. Chosen by Kyle, it never shows for Sam
    /// or a guest, who see the shared default list instead.
    @Test func aListOnlyItsOwnerMaySeeNeverShowsForAnyoneElse() {
        var settings = WidgetSettings()
        settings[Self.list] = "demo.tasks"
        household.recognize(kyle.id)
        #expect(shownList(settings)?.title == "My Tasks")
        household.recognize(sam.id)
        #expect(!service.visibleReminderLists.contains { $0.id == "demo.tasks" })
        #expect(shownList(settings)?.title == "Groceries")
        household.select(nil)
        #expect(shownList(settings)?.title == "Groceries")
    }

    /// A list deleted since it was chosen falls back to the default list.
    @Test func aDeletedListFallsBackToTheDefault() {
        household.recognize(kyle.id)
        var settings = WidgetSettings()
        settings[Self.list] = "demo.gone"
        #expect(shownList(settings)?.title == "Groceries")
    }
}
