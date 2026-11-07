import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

/// Same on All HomePads on the Home Screen: two iPads' settings stores, a
/// Home Favorites widget on its own and a Reminders widget in a stack, and
/// the layout carried between them as the shared setup carries it.
@MainActor @Suite struct HomeScreenSameOnAllHomePadsTests {
    static let lights = WidgetSettingKey<[String]?>("accessories", default: nil)
    static let list = WidgetSettingKey<String?>("list", default: nil)

    private let favoritesID = "widget:smarthome.favorites:F"
    private let stackID = "stack:S"
    private let remindersID = "reminders"

    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test.sameOnAll.\(UUID())")!)
    }

    private func layout() throws -> HomeScreenLayout {
        var favorites = HomeScreenItem.widget("smarthome.favorites", size: .large)
        favorites.instance = "F"
        var groceries = WidgetSettings()
        groceries[Self.list] = "groceries"
        let stack = WidgetStack(members: [WidgetStack.Member(id: remindersID, widgetID: "personal.reminders", settings: groceries),
                                          WidgetStack.Member(id: "weather", widgetID: "personal.weather")])
        let stacked = try #require(HomeScreenItem.stack(stack, size: .medium, instance: "S"))
        var layout = HomeScreenLayout(pages: [[favorites, stacked, .app("home")]], knownAppIDs: ["home"])
        layout.setSettings(lightsSettings(["hall"]), for: favoritesID)
        return layout
    }

    private func lightsSettings(_ lights: [String]) -> WidgetSettings {
        var settings = WidgetSettings()
        settings[Self.lights] = lights
        return settings
    }

    /// Edits the guest layout on one iPad.
    private func edit(_ settings: SettingsStore, _ change: (inout HomeScreenLayout) -> Void) throws {
        var layout = try #require(settings[ShellSettings.homeScreenLayout(for: nil)])
        change(&layout)
        settings[ShellSettings.homeScreenLayout(for: nil)] = layout
    }

    /// Carries the guest layout from one iPad to another, as the shared setup does.
    private func send(from here: SettingsStore, to there: SettingsStore) throws {
        guard case .content(let content) = HomeScreenSharing.readLayout(.household, settings: here) else {
            Issue.record("No layout to share")
            return
        }
        HomeScreenSharing.applyLayout(content, for: .household, settings: there)
        // Read right after applying, it is what arrived, so it is never sent back as a change.
        #expect(HomeScreenSharing.readLayout(.household, settings: there) == .content(content))
    }

    private func layout(_ settings: SettingsStore) throws -> HomeScreenLayout {
        try #require(settings[ShellSettings.homeScreenLayout(for: nil)])
    }

    /// Both iPads with the switch off for Home Favorites and for Reminders in
    /// the stack, each with its own lights and list.
    private func twoIPadsWithTheirOwn() throws -> (kitchen: SettingsStore, bedroom: SettingsStore) {
        let kitchen = makeSettings(), bedroom = makeSettings()
        kitchen[ShellSettings.homeScreenLayout(for: nil)] = try layout()
        try send(from: kitchen, to: bedroom)
        try edit(kitchen) { layout in
            var favorites = layout.settings(for: favoritesID)
            favorites.setSameOnAllHomePads(false)
            layout.setSettings(favorites, for: favoritesID)
            guard var stack = layout.stack(for: stackID) else { return }
            var reminders = stack.settings(for: remindersID)
            reminders.setSameOnAllHomePads(false)
            stack.setSettings(reminders, for: remindersID)
            layout.setStack(stack, for: stackID)
        }
        try send(from: kitchen, to: bedroom)
        try edit(kitchen) { layout in
            layout.setSettings(own(layout.settings(for: favoritesID), lights: ["kitchen"]), for: favoritesID)
        }
        try edit(bedroom) { layout in
            layout.setSettings(own(layout.settings(for: favoritesID), lights: ["bedroom"]), for: favoritesID)
            guard var stack = layout.stack(for: stackID) else { return }
            var reminders = stack.settings(for: remindersID)
            reminders[Self.list] = "bedtime"
            stack.setSettings(reminders, for: remindersID)
            layout.setStack(stack, for: stackID)
        }
        return (kitchen, bedroom)
    }

    private func own(_ settings: WidgetSettings, lights: [String]) -> WidgetSettings {
        var settings = settings
        settings[Self.lights] = lights
        return settings
    }

    @Test func eachIPadKeepsItsOwnSettingsForAWidgetAndOneInAStack() throws {
        let (kitchen, bedroom) = try twoIPadsWithTheirOwn()
        let shared = HomeScreenSharing.readLayout(.household, settings: kitchen)
        // Their own edits change nothing either of them shares.
        #expect(HomeScreenSharing.readLayout(.household, settings: bedroom) == shared)

        // A change elsewhere on the Home Screen arrives, and each keeps its own.
        try edit(kitchen) { $0.add(.app("music"), toPage: 0) }
        try send(from: kitchen, to: bedroom)
        #expect(try layout(bedroom).contains("app:music"))
        #expect(try layout(bedroom).settings(for: favoritesID)[Self.lights] == ["bedroom"])
        #expect(try layout(bedroom).stack(for: stackID)?.settings(for: remindersID)[Self.list] == "bedtime")
        #expect(try layout(kitchen).settings(for: favoritesID)[Self.lights] == ["kitchen"])
        #expect(try !layout(bedroom).settings(for: favoritesID).isSameOnAllHomePads)
        #expect(try layout(bedroom).allItems.map(\.id) == layout(kitchen).allItems.map(\.id))
    }

    /// A widget dragged out of the stack on one iPad keeps each iPad's own settings.
    @Test func ownSettingsMoveWithTheWidgetOutOfAStack() throws {
        let (kitchen, bedroom) = try twoIPadsWithTheirOwn()
        try edit(kitchen) { layout in
            guard var stack = layout.stack(for: stackID) else { return }
            stack.remove("weather")
            layout.setStack(stack, for: stackID)
        }
        try send(from: kitchen, to: bedroom)
        let reminders = try #require(layout(bedroom).allItems.first { $0.targetID == "personal.reminders" })
        #expect(!reminders.isStack)
        #expect(reminders.settings?[Self.list] == "bedtime")
    }

    @Test func turnedBackOnTheBedroomsSettingsReachTheKitchen() throws {
        let (kitchen, bedroom) = try twoIPadsWithTheirOwn()
        try edit(bedroom) { layout in
            var favorites = layout.settings(for: favoritesID)
            favorites.setSameOnAllHomePads(true)
            layout.setSettings(favorites, for: favoritesID)
        }
        try send(from: bedroom, to: kitchen)
        #expect(try layout(kitchen).settings(for: favoritesID) == lightsSettings(["bedroom"]))
        // Reminders in the stack is still kept on each.
        #expect(try layout(kitchen).stack(for: stackID)?.settings(for: remindersID)[Self.list] == "groceries")
    }

    /// An older HomePad decodes the layout as it always did and shows the
    /// settings the widget had when the switch went off. What it saves and
    /// sends back keeps the switch off on the newer one.
    @Test func anOlderHomePadReadsTheSharedCopyAndKeepsTheSwitch() throws {
        let (kitchen, _) = try twoIPadsWithTheirOwn()
        guard case .content(let content) = HomeScreenSharing.readLayout(.household, settings: kitchen) else {
            Issue.record("No layout to share")
            return
        }
        var older = try content.decoded(as: HomeScreenLayout.self)
        #expect(older.settings(for: favoritesID)[Self.lights] == ["hall"])
        #expect(older.stack(for: stackID)?.settings(for: remindersID)[Self.list] == "groceries")

        older.setSettings(own(older.settings(for: favoritesID), lights: ["older"]), for: favoritesID)
        HomeScreenSharing.applyLayout(try JSONValue(encoding: older), for: .household, settings: kitchen)
        #expect(try layout(kitchen).settings(for: favoritesID)[Self.lights] == ["kitchen"])
        #expect(try !layout(kitchen).settings(for: favoritesID).isSameOnAllHomePads)
    }

    /// Layouts saved before the switch read with it on for every widget.
    @Test func layoutsSavedBeforeTheSwitchReadAsTheSameOnAllHomePads() throws {
        let json = #"{"pages":[[{"kind":"widget","targetID":"personal.reminders","size":"large","instance":"A","settings":{"list":"groceries"}}]],"knownAppIDs":[]}"#
        let layout = try JSONDecoder().decode(HomeScreenLayout.self, from: Data(json.utf8))
        let settings = layout.settings(for: "widget:personal.reminders:A")
        #expect(settings.isSameOnAllHomePads)
        #expect(settings[Self.list] == "groceries")
        let content = try JSONValue(encoding: layout)
        #expect(content.sharingWidgetSettings() == content)
    }
}
