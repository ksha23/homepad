import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Two HomePads in memory that see one home under different HomeKit IDs,
/// trading their directories as the shared setup would.
@MainActor
@Suite struct HomeKitIDTranslatorTests {
    private typealias Entry = HomeKitDirectory.Entry
    private static let light = "00000043-0000-1000-8000-0026BB765291"

    /// One HomePad: its own settings and translator, and what Apple Home shows it.
    @MainActor
    private final class Pad {
        let id: String
        let defaults: UserDefaults
        let translator: HomeKitIDTranslator
        var changes = 0

        init(_ id: String, defaults: UserDefaults? = nil) {
            self.id = id
            self.defaults = defaults ?? UserDefaults(suiteName: "homekit-ids-\(id)-\(UUID().uuidString)")!
            translator = HomeKitIDTranslator(settings: SettingsStore(defaults: self.defaults))
            translator.onChange = { [unowned self] in changes += 1 }
        }

        /// Apple Home loaded or changed here.
        func show(_ entries: [Entry]) {
            translator.updateLocal(HomeKitDirectory(entries: entries))
        }

        /// What it shares now, as the shared setup reads it.
        var shared: HomeKitDirectory? {
            guard case .content(let content) = SmartHomeSharing.readDirectory(translator) else { return nil }
            return try? content.decoded(as: HomeKitDirectory.self)
        }

        func hear(_ other: Pad) {
            translator.receive(other.shared, from: other.id)
        }

        func id(for saved: String) -> String {
            translator.localID(for: saved)
        }
    }

    private func lamp(_ id: String, name: String = "Desk Lamp", room: String = "Office") -> Entry {
        Entry(id: id, kind: Self.light, home: "Home", room: room, name: name, accessory: name)
    }

    private func scene(_ id: String, _ name: String) -> Entry {
        Entry(id: id, kind: HomeKitDirectory.Kind.scene, home: "Home", name: name)
    }

    /// The kitchen (the 11-inch) and the office (the M4), paired.
    private func paired() -> (kitchen: Pad, office: Pad) {
        let kitchen = Pad("kitchen")
        let office = Pad("office")
        kitchen.show([lamp("hk:K1"), lamp("hk:K2", name: "Floor Lamp"), scene("hk:K3", "Good Night")])
        office.show([lamp("hk:O1"), lamp("hk:O2", name: "Floor Lamp"), scene("hk:O3", "Good Night")])
        kitchen.hear(office)
        office.hear(kitchen)
        return (kitchen, office)
    }

    @Test func eachHomePadReadsTheOthersIDsAsItsOwn() {
        let (kitchen, office) = paired()
        #expect(office.id(for: "hk:K1") == "hk:O1")
        #expect(office.id(for: "hk:K2") == "hk:O2")
        #expect(office.id(for: "hk:K3") == "hk:O3")
        #expect(kitchen.id(for: "hk:O1") == "hk:K1")
        // Its own IDs, Home Assistant's and unknown ones stand for themselves.
        #expect(office.id(for: "hk:O1") == "hk:O1")
        #expect(office.id(for: "ha:light.kitchen") == "ha:light.kitchen")
        #expect(office.id(for: "hk:unknown") == "hk:unknown")
        #expect(office.changes == 1)
    }

    @Test func nothingIsSharedBeforeAppleHomeLoads() {
        let office = Pad("office")
        if case .onlyThisHomePad = SmartHomeSharing.readDirectory(office.translator) {} else {
            Issue.record("A HomePad whose Apple Home has not loaded keeps what it shared before")
        }
        // What it heard still counts once Apple Home loads.
        let kitchen = Pad("kitchen")
        kitchen.show([lamp("hk:K1")])
        office.hear(kitchen)
        #expect(office.id(for: "hk:K1") == "hk:K1")
        office.show([lamp("hk:O1")])
        #expect(office.id(for: "hk:K1") == "hk:O1")
    }

    @Test func aRenameOnEveryIPadKeepsThePair() {
        let (kitchen, office) = paired()
        // HomeKit carries a rename to every iPad, and both share their new directory.
        kitchen.show([lamp("hk:K1", name: "Work Lamp"), lamp("hk:K2", name: "Floor Lamp"), scene("hk:K3", "Good Night")])
        office.show([lamp("hk:O1", name: "Work Lamp"), lamp("hk:O2", name: "Floor Lamp"), scene("hk:O3", "Good Night")])
        kitchen.hear(office)
        office.hear(kitchen)
        #expect(office.id(for: "hk:K1") == "hk:O1")
        #expect(kitchen.id(for: "hk:O1") == "hk:K1")
    }

    @Test func aRenameWhileTheOtherHomePadIsOffKeepsThePair() {
        let (_, office) = paired()
        // The kitchen is off, so the office holds its directory with the old name.
        office.show([lamp("hk:O1", name: "Work Lamp"), lamp("hk:O2", name: "Floor Lamp"), scene("hk:O3", "Good Night")])
        #expect(office.id(for: "hk:K1") == "hk:O1")

        // And after the office restarts, before and after its Apple Home loads.
        let restarted = Pad("office", defaults: office.defaults)
        #expect(restarted.id(for: "hk:K1") == "hk:O1")
        restarted.show([lamp("hk:O1", name: "Work Lamp"), lamp("hk:O2", name: "Floor Lamp"), scene("hk:O3", "Good Night")])
        #expect(restarted.id(for: "hk:K1") == "hk:O1")
        #expect(restarted.id(for: "hk:K2") == "hk:O2")
    }

    @Test func aSecondAccessoryWithTheSameNameKeepsAPairMadeBefore() {
        let (kitchen, office) = paired()
        kitchen.show([lamp("hk:K1"), lamp("hk:K9"), lamp("hk:K2", name: "Floor Lamp"), scene("hk:K3", "Good Night")])
        office.show([lamp("hk:O1"), lamp("hk:O9"), lamp("hk:O2", name: "Floor Lamp"), scene("hk:O3", "Good Night")])
        kitchen.hear(office)
        office.hear(kitchen)
        #expect(office.id(for: "hk:K1") == "hk:O1")
        // The new one was never certain, so it shows nothing rather than the wrong lamp.
        #expect(office.id(for: "hk:K9") == "hk:K9")
    }

    @Test func twoThatMatchFromTheStartPairWithNothing() {
        let kitchen = Pad("kitchen")
        let office = Pad("office")
        kitchen.show([lamp("hk:K1"), lamp("hk:K2")])
        office.show([lamp("hk:O1"), lamp("hk:O2")])
        office.hear(kitchen)
        #expect(office.id(for: "hk:K1") == "hk:K1")
        #expect(office.id(for: "hk:K2") == "hk:K2")
    }

    @Test func aRemovedAccessoryLosesItsPair() {
        let (kitchen, office) = paired()
        kitchen.show([lamp("hk:K2", name: "Floor Lamp"), scene("hk:K3", "Good Night")])
        office.show([lamp("hk:O2", name: "Floor Lamp"), scene("hk:O3", "Good Night")])
        office.hear(kitchen)
        #expect(office.id(for: "hk:K1") == "hk:K1")
        #expect(office.id(for: "hk:K2") == "hk:O2")
    }

    @Test func aThirdHomePadReadsBothOthers() {
        let (kitchen, office) = paired()
        let bedroom = Pad("bedroom")
        bedroom.show([lamp("hk:B1"), lamp("hk:B2", name: "Floor Lamp"), scene("hk:B3", "Good Night")])
        bedroom.hear(kitchen)
        bedroom.hear(office)
        #expect(bedroom.id(for: "hk:K1") == "hk:B1")
        #expect(bedroom.id(for: "hk:O2") == "hk:B2")
        #expect(Set(bedroom.translator.otherDirectories.keys) == ["kitchen", "office"])
    }
}
