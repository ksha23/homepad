import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// A guest Home Screen in miniature: its apps, and a Home Favorites widget with its settings.
struct MiniHomeScreen: Codable, Equatable {
    var apps: [String]
    var favorites: WidgetSettings
}

extension TestHomePad {
    /// The guest Home Screen as this HomePad shows it.
    var guestScreen: MiniHomeScreen? {
        try? layouts[.household]?.decoded(as: MiniHomeScreen.self)
    }

    /// The lights its Home Favorites widget shows.
    var favoriteLights: [String]? {
        guestScreen?.favorites[SameOnAllHomePadsTests.lights]
    }

    /// Changes the guest Home Screen here and shares what changed, as an edit on the iPad does.
    func editGuestScreen(_ change: (inout MiniHomeScreen) -> Void) {
        edit { pad in
            guard var screen = pad.guestScreen else { return }
            change(&screen)
            pad.layouts[.household] = try? JSONValue(encoding: screen)
        }
    }
}

/// Same on All HomePads between two HomePads in memory: a Home Favorites
/// widget that shows the kitchen's lights in the kitchen and the bedroom's in
/// the bedroom, while the widget itself stays where it is on both.
@MainActor
@Suite struct SameOnAllHomePadsTests {
    static let lights = WidgetSettingKey<[String]?>("accessories", default: nil)

    private struct Home {
        let network: SetupNetwork
        let kitchen: TestHomePad
        let bedroom: TestHomePad
    }

    /// Two HomePads that share a guest Home Screen whose Home Favorites shows the hall lights.
    private func home(bedroomIsOlder: Bool = false) throws -> Home {
        let network = SetupNetwork()
        let kitchen = TestHomePad("A-kitchen", installedAt: Date(timeIntervalSince1970: 1_700_000_000), network: network)
        let bedroom = TestHomePad("B-bedroom", installedAt: Date(timeIntervalSince1970: 1_750_000_000),
                                  isOlderBuild: bedroomIsOlder, network: network)
        var favorites = WidgetSettings()
        favorites[Self.lights] = ["hall"]
        kitchen.layouts[.household] = try JSONValue(encoding: MiniHomeScreen(apps: ["home"], favorites: favorites))
        network.connect(kitchen, bedroom)
        return Home(network: network, kitchen: kitchen, bedroom: bedroom)
    }

    @Test func turnedOffEachHomePadKeepsItsOwnSettingsAndTheirEditsStayThere() throws {
        let home = try home()
        #expect(home.bedroom.favoriteLights == ["hall"])

        // The switch itself reaches the bedroom, which starts from what it had.
        home.kitchen.editGuestScreen { $0.favorites.setSameOnAllHomePads(false) }
        #expect(home.bedroom.guestScreen?.favorites.isSameOnAllHomePads == false)
        #expect(home.bedroom.favoriteLights == ["hall"])

        // Each picks its own lights, and nothing travels.
        home.network.resetCount()
        home.kitchen.editGuestScreen { $0.favorites[Self.lights] = ["kitchen"] }
        home.bedroom.editGuestScreen { $0.favorites[Self.lights] = ["bedroom"] }
        #expect(home.network.delivered.isEmpty)
        #expect(home.kitchen.favoriteLights == ["kitchen"])
        #expect(home.bedroom.favoriteLights == ["bedroom"])

        // The rest of the Home Screen is still shared, and each keeps its lights.
        home.bedroom.editGuestScreen { $0.apps.append("music") }
        #expect(home.kitchen.guestScreen?.apps == ["home", "music"])
        #expect(home.kitchen.favoriteLights == ["kitchen"])
        #expect(home.bedroom.favoriteLights == ["bedroom"])
        #expect(home.kitchen.guestScreen?.favorites.isSameOnAllHomePads == false)
    }

    @Test func turnedBackOnThisHomePadsSettingsBecomeTheSharedOnes() throws {
        let home = try home()
        home.kitchen.editGuestScreen { $0.favorites.setSameOnAllHomePads(false) }
        home.kitchen.editGuestScreen { $0.favorites[Self.lights] = ["kitchen"] }
        home.bedroom.editGuestScreen { $0.favorites[Self.lights] = ["bedroom"] }

        home.bedroom.editGuestScreen { $0.favorites.setSameOnAllHomePads(true) }
        #expect(home.kitchen.favoriteLights == ["bedroom"])
        #expect(home.kitchen.guestScreen?.favorites.isSameOnAllHomePads == true)
        #expect(home.kitchen.guestScreen == home.bedroom.guestScreen)

        // Shared again, an edit on either reaches the other.
        home.kitchen.editGuestScreen { $0.favorites[Self.lights] = ["kitchen", "pantry"] }
        #expect(home.bedroom.favoriteLights == ["kitchen", "pantry"])
    }

    @Test func aHomePadThatWasOffCatchesUpAndKeepsItsOwnSettings() throws {
        let home = try home()
        home.kitchen.editGuestScreen { $0.favorites.setSameOnAllHomePads(false) }
        home.bedroom.editGuestScreen { $0.favorites[Self.lights] = ["bedroom"] }

        home.network.disconnect(home.kitchen, home.bedroom)
        home.kitchen.editGuestScreen { $0.apps.append("timers") }
        home.kitchen.editGuestScreen { $0.favorites[Self.lights] = ["kitchen"] }
        home.network.connect(home.kitchen, home.bedroom)
        #expect(home.bedroom.guestScreen?.apps == ["home", "timers"])
        #expect(home.bedroom.favoriteLights == ["bedroom"])
        #expect(home.kitchen.favoriteLights == ["kitchen"])
    }

    /// An older HomePad keeps showing the settings the widget had when the
    /// switch went off, and its own changes to the layout or the widget are
    /// neither lost there nor taken by the newer HomePad as its own settings.
    @Test func anOlderHomePadShowsTheSettingsFromWhenTheSwitchWentOffAndLosesNothing() throws {
        let home = try home(bedroomIsOlder: true)
        home.kitchen.editGuestScreen { $0.favorites.setSameOnAllHomePads(false) }
        home.kitchen.editGuestScreen { $0.favorites[Self.lights] = ["kitchen"] }
        #expect(home.bedroom.favoriteLights == ["hall"])

        // Its own edits to the layout still reach the kitchen, which keeps its lights and its switch.
        home.bedroom.editGuestScreen { $0.apps.append("music") }
        #expect(home.kitchen.guestScreen?.apps == ["home", "music"])
        #expect(home.kitchen.favoriteLights == ["kitchen"])
        #expect(home.kitchen.guestScreen?.favorites.isSameOnAllHomePads == false)

        // It changes the widget as if it were shared. The kitchen keeps its own,
        // and the older HomePad keeps its change through the kitchen's next edit.
        home.bedroom.editGuestScreen { $0.favorites[Self.lights] = ["bedroom"] }
        #expect(home.kitchen.favoriteLights == ["kitchen"])
        home.kitchen.editGuestScreen { $0.apps.append("timers") }
        #expect(home.bedroom.guestScreen?.apps == ["home", "music", "timers"])
        #expect(home.bedroom.favoriteLights == ["bedroom"])
    }

    @Test func eachHomePadSaysHowManyOthersShareItsSetup() throws {
        let network = SetupNetwork()
        let kitchen = TestHomePad("A-kitchen", installedAt: Date(timeIntervalSince1970: 1_700_000_000), network: network)
        let bedroom = TestHomePad("B-bedroom", installedAt: Date(timeIntervalSince1970: 1_750_000_000), network: network)
        var counts: [Int] = []
        kitchen.sync.onPeerCountChange = { counts.append($0) }
        network.connect(kitchen, bedroom)
        #expect(counts == [1])
    }
}
