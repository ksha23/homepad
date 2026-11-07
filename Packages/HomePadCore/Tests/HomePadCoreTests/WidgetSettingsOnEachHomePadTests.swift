import Foundation
import Testing
@testable import HomePadCore

/// Same on All HomePads: a widget whose settings each HomePad keeps for itself,
/// and how a shared document carries it.
@Suite struct WidgetSettingsOnEachHomePadTests {
    static let lights = WidgetSettingKey<[String]?>("accessories", default: nil)

    private func settings(_ lights: [String]) -> WidgetSettings {
        var settings = WidgetSettings()
        settings[Self.lights] = lights
        return settings
    }

    /// A document with widgets in two places, as a Home Screen keeps one on its own and one in a stack.
    private func document(single: WidgetSettings, stacked: WidgetSettings) throws -> JSONValue {
        let page = JSONValue.array([.object(["settings": try JSONValue(encoding: single)])])
        let stack = JSONValue.object(["settings": try JSONValue(encoding: stacked)])
        return .object(["pages": .array([page]), "stacks": .array([stack])])
    }

    private func single(in document: JSONValue) throws -> WidgetSettings {
        let item = try #require(document["pages"]?.arrayValue?.first?.arrayValue?.first)
        return try #require(item["settings"]).decoded(as: WidgetSettings.self)
    }

    @Test func widgetsStartTheSameOnAllHomePadsAndSettingsSavedBeforeTheSwitchReadAsOn() throws {
        #expect(WidgetSettings().isSameOnAllHomePads)
        let saved = try JSONDecoder().decode(WidgetSettings.self, from: Data(#"{"accessories":["kitchen"]}"#.utf8))
        #expect(saved.isSameOnAllHomePads)
        #expect(saved[Self.lights] == ["kitchen"])
    }

    @Test func turnedOffTheSettingsStayAndTheSharedCopyIsWhatTheyWere() {
        var kitchen = settings(["kitchen"])
        kitchen.setSameOnAllHomePads(false)
        #expect(!kitchen.isSameOnAllHomePads)
        #expect(kitchen[Self.lights] == ["kitchen"])

        // Edits here change this iPad's own settings, never what is shared.
        let shared = kitchen.forSharing
        kitchen[Self.lights] = ["kitchen", "pantry"]
        #expect(kitchen.forSharing == shared)
        #expect(shared[Self.lights] == ["kitchen"])
        #expect(!shared.isSameOnAllHomePads)

        // Back on, this iPad's settings are the shared ones.
        kitchen.setSameOnAllHomePads(true)
        #expect(kitchen.isSameOnAllHomePads)
        #expect(kitchen.forSharing == settings(["kitchen", "pantry"]))
    }

    @Test func aDocumentFromAnotherHomePadKeepsThisIPadsOwnSettings() throws {
        var kitchen = settings(["kitchen"])
        kitchen.setSameOnAllHomePads(false)
        let sent = try document(single: kitchen, stacked: settings(["hall"])).sharingWidgetSettings()

        // The bedroom has its own settings for the widget, saved while the switch was off.
        var bedroom = kitchen.keepingOwn([:])
        bedroom[Self.lights] = ["bedroom"]
        let local = try document(single: bedroom, stacked: settings(["hall"]))

        let kept = sent.keepingOwnWidgetSettings(from: local)
        #expect(try single(in: kept)[Self.lights] == ["bedroom"])
        #expect(try !single(in: kept).isSameOnAllHomePads)
        // Read right after, it is what arrived, so it is never sent back as a change.
        #expect(kept.sharingWidgetSettings() == sent)
    }

    @Test func aHomePadWithNoSettingsOfItsOwnYetStartsFromTheSharedCopy() throws {
        var kitchen = settings(["kitchen"])
        kitchen.setSameOnAllHomePads(false)
        kitchen[Self.lights] = ["kitchen", "pantry"]
        let sent = try document(single: kitchen, stacked: WidgetSettings()).sharingWidgetSettings()

        let kept = sent.keepingOwnWidgetSettings(from: nil)
        #expect(try single(in: kept)[Self.lights] == ["kitchen"])
        #expect(kept.sharingWidgetSettings() == sent)
    }

    /// Moved into a stack on one HomePad, the widget keeps each HomePad's own settings.
    @Test func ownSettingsFollowTheWidgetWhereverItSits() throws {
        var kitchen = settings(["kitchen"])
        kitchen.setSameOnAllHomePads(false)
        var bedroom = kitchen.keepingOwn([:])
        bedroom[Self.lights] = ["bedroom"]
        let local = try document(single: bedroom, stacked: WidgetSettings())

        let moved = try document(single: WidgetSettings(), stacked: kitchen).sharingWidgetSettings()
        let kept = moved.keepingOwnWidgetSettings(from: local)
        let stacked = try #require(kept["stacks"]?.arrayValue?.first?["settings"]).decoded(as: WidgetSettings.self)
        #expect(stacked[Self.lights] == ["bedroom"])
    }

    @Test func widgetsTheSameOnAllHomePadsPassThroughUnchanged() throws {
        let plain = try document(single: settings(["kitchen"]), stacked: WidgetSettings())
        #expect(plain.sharingWidgetSettings() == plain)
        #expect(plain.keepingOwnWidgetSettings(from: plain) == plain)
        #expect(JSONValue.string("a layout").sharingWidgetSettings() == .string("a layout"))
    }

    /// Turned back on elsewhere, the other HomePad's settings arrive like any change.
    @Test func turnedBackOnElsewhereTheirSettingsArrive() throws {
        var bedroom = settings(["kitchen"])
        bedroom.setSameOnAllHomePads(false)
        bedroom[Self.lights] = ["bedroom"]
        let local = try document(single: bedroom, stacked: WidgetSettings())
        let sent = try document(single: settings(["kitchen", "pantry"]), stacked: WidgetSettings())
        let kept = sent.keepingOwnWidgetSettings(from: local)
        #expect(try single(in: kept) == settings(["kitchen", "pantry"]))
    }
}
