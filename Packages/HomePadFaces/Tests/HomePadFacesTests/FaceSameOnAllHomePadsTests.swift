import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

/// Same on All HomePads on a face: two iPads' face libraries, a Home
/// Favorites widget on its own and a Reminders widget in a stack, and the
/// saved faces carried between them as the shared setup carries them.
@MainActor @Suite struct FaceSameOnAllHomePadsTests {
    static let lights = WidgetSettingKey<[String]?>("accessories", default: nil)
    static let list = WidgetSettingKey<String?>("list", default: nil)

    private let faceID = UUID(uuidString: "0F0F0F0F-0000-4000-8000-0000000000A1")!
    private let favoritesID = UUID(uuidString: "0F0F0F0F-0000-4000-8000-0000000000B1")!
    private let stackID = UUID(uuidString: "0F0F0F0F-0000-4000-8000-0000000000B2")!
    private let legacySize = WidgetSize.medium

    private func makeLibrary() -> FaceLibrary {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "faces.sameOnAll.\(UUID())")!)
        return FaceLibrary(settings: settings, household: Household(store: settings))
    }

    private func face() -> FaceConfiguration {
        let placements = [FaceWidgetPlacement(id: favoritesID, widgetID: "smarthome.favorites", size: .large),
                          FaceWidgetPlacement(id: stackID, widgetID: "personal.reminders", size: .medium)]
        var face = FaceConfiguration(id: faceID, faceID: "faces.modular", widgetLayout: FaceWidgetLayout(landscape: placements))
        var hall = WidgetSettings()
        hall[Self.lights] = ["hall"]
        face.setWidgetSettings(hall, for: favoritesID, legacySize: legacySize)
        var groceries = WidgetSettings()
        groceries[Self.list] = "groceries"
        let stack = WidgetStack(members: [WidgetStack.Member(id: "reminders", widgetID: "personal.reminders", settings: groceries),
                                          WidgetStack.Member(id: "weather", widgetID: "personal.weather")])
        face.setWidgetStack(stack, for: stackID, legacySize: legacySize)
        return face
    }

    /// Changes the face on one iPad, as the editor's Done saves it.
    private func edit(_ library: FaceLibrary, owner: FaceOwner = .household, _ change: (inout FaceConfiguration) -> Void) throws {
        var face = try #require(library.list(for: owner).faces.first { $0.id == faceID })
        change(&face)
        library.save(face, for: owner)
    }

    /// Carries an owner's faces from one iPad to another, as the shared setup does.
    private func send(from here: FaceLibrary, to there: FaceLibrary, owner: FaceOwner = .household) {
        guard case .content(let content) = FaceSharing.readLibrary(owner, library: here) else {
            Issue.record("No faces to share")
            return
        }
        FaceSharing.applyLibrary(content, for: owner, library: there)
        // Read right after applying, it is what arrived, so it is never sent back as a change.
        #expect(FaceSharing.readLibrary(owner, library: there) == .content(content))
    }

    private func shown(_ library: FaceLibrary, owner: FaceOwner = .household) throws -> FaceConfiguration {
        try #require(library.list(for: owner).faces.first { $0.id == faceID })
    }

    private func lights(_ library: FaceLibrary, owner: FaceOwner = .household) throws -> [String]? {
        try shown(library, owner: owner).widgetSettings(for: favoritesID, legacySize: legacySize)[Self.lights]
    }

    private func reminders(_ library: FaceLibrary) throws -> String? {
        try shown(library).widgetStack(for: stackID, legacySize: legacySize)?.settings(for: "reminders")[Self.list]
    }

    /// Both iPads with the switch off for Home Favorites and for Reminders in
    /// the stack, each with its own lights and list.
    private func twoIPadsWithTheirOwn() throws -> (kitchen: FaceLibrary, bedroom: FaceLibrary) {
        let kitchen = makeLibrary(), bedroom = makeLibrary()
        kitchen.save(face(), for: .household)
        send(from: kitchen, to: bedroom)
        try edit(kitchen) { face in
            var favorites = face.widgetSettings(for: favoritesID, legacySize: legacySize)
            favorites.setSameOnAllHomePads(false)
            face.setWidgetSettings(favorites, for: favoritesID, legacySize: legacySize)
            guard var stack = face.widgetStack(for: stackID, legacySize: legacySize) else { return }
            var reminders = stack.settings(for: "reminders")
            reminders.setSameOnAllHomePads(false)
            stack.setSettings(reminders, for: "reminders")
            face.setWidgetStack(stack, for: stackID, legacySize: legacySize)
        }
        send(from: kitchen, to: bedroom)
        try edit(kitchen) { setLights(["kitchen"], in: &$0) }
        try edit(bedroom) { face in
            setLights(["bedroom"], in: &face)
            guard var stack = face.widgetStack(for: stackID, legacySize: legacySize) else { return }
            var reminders = stack.settings(for: "reminders")
            reminders[Self.list] = "bedtime"
            stack.setSettings(reminders, for: "reminders")
            face.setWidgetStack(stack, for: stackID, legacySize: legacySize)
        }
        return (kitchen, bedroom)
    }

    private func setLights(_ lights: [String], in face: inout FaceConfiguration) {
        var settings = face.widgetSettings(for: favoritesID, legacySize: legacySize)
        settings[Self.lights] = lights
        face.setWidgetSettings(settings, for: favoritesID, legacySize: legacySize)
    }

    @Test func eachIPadKeepsItsOwnSettingsForAFaceWidgetAndOneInAStack() throws {
        let (kitchen, bedroom) = try twoIPadsWithTheirOwn()
        #expect(FaceSharing.readLibrary(.household, library: bedroom) == FaceSharing.readLibrary(.household, library: kitchen))

        // A change to the face arrives, and each keeps its own.
        try edit(kitchen) { $0.values["style"] = "digital" }
        send(from: kitchen, to: bedroom)
        #expect(try shown(bedroom).values["style"] == "digital")
        #expect(try lights(bedroom) == ["bedroom"])
        #expect(try reminders(bedroom) == "bedtime")
        #expect(try lights(kitchen) == ["kitchen"])
        #expect(try reminders(kitchen) == "groceries")
        #expect(try !shown(bedroom).widgetSettings(for: favoritesID, legacySize: legacySize).isSameOnAllHomePads)
    }

    /// A person's faces start as a copy of the household's on their first
    /// edit. The other iPad keeps its own settings in that copy too.
    @Test func aPersonsFirstOwnFacesKeepTheOtherIPadsOwnSettings() throws {
        let (kitchen, bedroom) = try twoIPadsWithTheirOwn()
        let kyle = FaceOwner.member(UUID())
        try edit(kitchen, owner: kyle) { $0.values["style"] = "analog" }
        send(from: kitchen, to: bedroom, owner: kyle)
        #expect(try lights(bedroom, owner: kyle) == ["bedroom"])
        #expect(try lights(kitchen, owner: kyle) == ["kitchen"])
    }

    @Test func turnedBackOnTheKitchensSettingsReachTheBedroom() throws {
        let (kitchen, bedroom) = try twoIPadsWithTheirOwn()
        try edit(kitchen) { face in
            var favorites = face.widgetSettings(for: favoritesID, legacySize: legacySize)
            favorites.setSameOnAllHomePads(true)
            face.setWidgetSettings(favorites, for: favoritesID, legacySize: legacySize)
        }
        send(from: kitchen, to: bedroom)
        #expect(try lights(bedroom) == ["kitchen"])
        #expect(try shown(bedroom).widgetSettings(for: favoritesID, legacySize: legacySize).isSameOnAllHomePads)
        #expect(try reminders(bedroom) == "bedtime")
    }

    /// An older HomePad decodes the faces as it always did and shows the
    /// settings each widget had when the switch went off.
    @Test func anOlderHomePadReadsTheSharedCopy() throws {
        let (kitchen, _) = try twoIPadsWithTheirOwn()
        guard case .content(let content) = FaceSharing.readLibrary(.household, library: kitchen) else {
            Issue.record("No faces to share")
            return
        }
        let older = try content.decoded(as: SavedFaceList.self)
        let face = try #require(older.faces.first { $0.id == faceID })
        #expect(face.widgetSettings(for: favoritesID, legacySize: legacySize)[Self.lights] == ["hall"])
        #expect(face.widgetStack(for: stackID, legacySize: legacySize)?.settings(for: "reminders")[Self.list] == "groceries")
    }
}
