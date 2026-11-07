import Foundation
import Testing
@testable import HomePadSmartHome

/// Two HomePads see the same home with different HomeKit IDs. The matcher
/// pairs each object with its twin by home, room, name and kind, and pairs
/// nothing it is not sure of.
@Suite struct HomeKitIDMatcherTests {
    private typealias Entry = HomeKitDirectory.Entry
    private static let light = "00000043-0000-1000-8000-0026BB765291"
    private static let outlet = "00000047-0000-1000-8000-0026BB765291"

    private func lamp(_ id: String, room: String = "Office", name: String = "Desk Lamp", accessory: String? = nil) -> Entry {
        Entry(id: id, kind: Self.light, home: "Home", room: room, name: name, accessory: accessory ?? name)
    }

    @Test func pairsTheSameObjectsUnderDifferentIDs() {
        let kitchen = HomeKitDirectory(entries: [
            lamp("hk:K1"),
            Entry(id: "hk:K2", kind: Self.outlet, home: "Home", room: "Kitchen", name: "Coffee", accessory: "Coffee"),
            Entry(id: "hk:K3", kind: HomeKitDirectory.Kind.scene, home: "Home", name: "Good Night"),
            Entry(id: "hk:K4", kind: HomeKitDirectory.Kind.camera, home: "Home", room: "Porch", name: "Front Door"),
            Entry(id: "hk:K5", kind: HomeKitDirectory.Kind.group, home: "Home", name: "Downstairs"),
        ])
        let office = HomeKitDirectory(entries: [
            lamp("hk:O1"),
            Entry(id: "hk:O2", kind: Self.outlet, home: "Home", room: "Kitchen", name: "Coffee", accessory: "Coffee"),
            Entry(id: "hk:O3", kind: HomeKitDirectory.Kind.scene, home: "Home", name: "Good Night"),
            Entry(id: "hk:O4", kind: HomeKitDirectory.Kind.camera, home: "Home", room: "Porch", name: "Front Door"),
            Entry(id: "hk:O5", kind: HomeKitDirectory.Kind.group, home: "Home", name: "Downstairs"),
        ])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: office)
                == ["hk:K1": "hk:O1", "hk:K2": "hk:O2", "hk:K3": "hk:O3", "hk:K4": "hk:O4", "hk:K5": "hk:O5"])
        #expect(HomeKitIDMatcher.translations(from: office, to: kitchen)
                == ["hk:O1": "hk:K1", "hk:O2": "hk:K2", "hk:O3": "hk:K3", "hk:O4": "hk:K4", "hk:O5": "hk:K5"])
    }

    @Test func namesAndRoomsIgnoreCaseAccentsAndSpaces() {
        let kitchen = HomeKitDirectory(entries: [lamp("hk:K1", room: "Café  Corner", name: " Desk Lamp ")])
        let office = HomeKitDirectory(entries: [lamp("hk:O1", room: "cafe corner", name: "desk lamp")])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: office) == ["hk:K1": "hk:O1"])
    }

    @Test func aDifferentKindRoomOrHomeIsAnotherObject() {
        let kitchen = HomeKitDirectory(entries: [lamp("hk:K1")])
        let elsewhere = HomeKitDirectory(entries: [
            lamp("hk:O1", room: "Bedroom"),
            Entry(id: "hk:O2", kind: Self.outlet, home: "Home", room: "Office", name: "Desk Lamp", accessory: "Desk Lamp"),
            Entry(id: "hk:O3", kind: Self.light, home: "Cabin", room: "Office", name: "Desk Lamp", accessory: "Desk Lamp"),
        ])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: elsewhere).isEmpty)
    }

    @Test func twoThatMatchPairWithNothing() {
        let kitchen = HomeKitDirectory(entries: [lamp("hk:K1"), lamp("hk:K2")])
        let office = HomeKitDirectory(entries: [lamp("hk:O1"), lamp("hk:O2")])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: office).isEmpty)
    }

    @Test func theAccessoryNameTellsTwoServicesApart() {
        // A ceiling fan and a floor fan, each with a light named "Light".
        let kitchen = HomeKitDirectory(entries: [
            lamp("hk:K1", name: "Light", accessory: "Ceiling Fan"),
            lamp("hk:K2", name: "Light", accessory: "Floor Fan"),
        ])
        let office = HomeKitDirectory(entries: [
            lamp("hk:O2", name: "Light", accessory: "Floor Fan"),
            lamp("hk:O1", name: "Light", accessory: "ceiling fan"),
        ])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: office) == ["hk:K1": "hk:O1", "hk:K2": "hk:O2"])
    }

    @Test func twoOfTheirsNeverPairWithOneOfOurs() {
        // Their directory still has two lights where this HomePad has one.
        let kitchen = HomeKitDirectory(entries: [
            lamp("hk:K1", name: "Light", accessory: "Ceiling Fan"),
            lamp("hk:K2", name: "Light", accessory: "Floor Fan"),
        ])
        let office = HomeKitDirectory(entries: [lamp("hk:O1", name: "Light", accessory: "Ceiling Fan")])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: office) == ["hk:K1": "hk:O1"])

        // And with the accessory renamed too, neither is certain.
        let renamed = HomeKitDirectory(entries: [lamp("hk:O1", name: "Light", accessory: "Big Fan")])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: renamed).isEmpty)
    }

    @Test func aMissingObjectPairsWithNothing() {
        let kitchen = HomeKitDirectory(entries: [lamp("hk:K1"), lamp("hk:K2", name: "Floor Lamp")])
        let office = HomeKitDirectory(entries: [lamp("hk:O1")])
        #expect(HomeKitIDMatcher.translations(from: kitchen, to: office) == ["hk:K1": "hk:O1"])
    }

    @Test func entriesAreSortedSoTheSameObjectsMakeTheSameDocument() {
        let one = HomeKitDirectory(entries: [lamp("hk:B"), lamp("hk:A", name: "Floor Lamp")])
        let two = HomeKitDirectory(entries: [lamp("hk:A", name: "Floor Lamp"), lamp("hk:B")])
        #expect(one == two)
        #expect(one.entries.map(\.id) == ["hk:A", "hk:B"])
    }
}
