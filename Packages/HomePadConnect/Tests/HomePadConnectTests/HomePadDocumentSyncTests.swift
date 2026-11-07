import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Each HomePad's own document (`HomePadDocumentDescriptor`), such as the
/// names it knows its HomeKit accessories by: every HomePad keeps the latest
/// one of every other, and none overwrites another's.
@MainActor
@Suite struct HomePadDocumentSyncTests {
    private static let kind = "test.about"

    /// What one test HomePad says about itself, and what it heard from the others.
    @MainActor
    private final class About {
        /// Nil while it is not known yet, which keeps what was shared.
        var own: String?
        var heard: [String: String] = [:]
    }

    private func pad(_ id: String, installedAt seconds: TimeInterval, network: SetupNetwork) -> (TestHomePad, About) {
        let pad = TestHomePad(id, installedAt: Date(timeIntervalSince1970: seconds), network: network)
        let about = About()
        pad.registry.register(homePadDocument: HomePadDocumentDescriptor(
            id: Self.kind,
            read: { about.own.map { .content(.string($0)) } ?? .onlyThisHomePad },
            apply: { homePad, content in about.heard[homePad] = content?.stringValue }
        ))
        return (pad, about)
    }

    @Test func eachHomePadKeepsTheOthersDocumentAndNeitherOverwritesTheOther() {
        let network = SetupNetwork()
        let (kitchen, kitchenAbout) = pad("A-kitchen", installedAt: 1_700_000_000, network: network)
        let (office, officeAbout) = pad("B-office", installedAt: 1_750_000_000, network: network)
        kitchenAbout.own = "kitchen names"
        officeAbout.own = "office names"
        network.connect(kitchen, office)

        #expect(kitchenAbout.heard == ["B-office": "office names"])
        #expect(officeAbout.heard == ["A-kitchen": "kitchen names"])

        // Both change at the same moment: each keeps the other's latest.
        kitchenAbout.own = "kitchen names, renamed"
        officeAbout.own = "office names, renamed"
        kitchen.sync.shareLocalChanges()
        office.sync.shareLocalChanges()
        network.deliverAll()
        #expect(kitchenAbout.heard == ["B-office": "office names, renamed"])
        #expect(officeAbout.heard == ["A-kitchen": "kitchen names, renamed"])
    }

    @Test func aHomePadThatIsOffStillReachesANewOneThroughAnother() {
        let network = SetupNetwork()
        let (kitchen, kitchenAbout) = pad("A-kitchen", installedAt: 1_700_000_000, network: network)
        let (office, officeAbout) = pad("B-office", installedAt: 1_750_000_000, network: network)
        let (bedroom, bedroomAbout) = pad("C-bedroom", installedAt: 1_760_000_000, network: network)
        kitchenAbout.own = "kitchen names"
        officeAbout.own = "office names"
        bedroomAbout.own = "bedroom names"
        network.connect(kitchen, office)
        network.disconnect(kitchen, office)

        // The kitchen is off. The bedroom joins through the office alone.
        network.connect(office, bedroom)
        #expect(bedroomAbout.heard == ["A-kitchen": "kitchen names", "B-office": "office names"])
        #expect(officeAbout.heard == ["A-kitchen": "kitchen names", "C-bedroom": "bedroom names"])
    }

    @Test func aDocumentNotKnownYetKeepsWhatWasShared() {
        let network = SetupNetwork()
        let (kitchen, kitchenAbout) = pad("A-kitchen", installedAt: 1_700_000_000, network: network)
        let (office, officeAbout) = pad("B-office", installedAt: 1_750_000_000, network: network)
        kitchenAbout.own = "kitchen names"
        network.connect(kitchen, office)
        #expect(officeAbout.heard == ["A-kitchen": "kitchen names"])

        // Apple Home still loading after a restart: nothing goes out, and the office keeps the copy it has.
        kitchenAbout.own = nil
        network.resetCount()
        kitchen.sync.shareLocalChanges()
        network.deliverAll()
        #expect(network.delivered.isEmpty)
        #expect(officeAbout.heard == ["A-kitchen": "kitchen names"])
    }

    @Test func itsOwnDocumentComingBackOlderIsAnsweredWithTheCurrentOne() {
        let network = SetupNetwork()
        let (kitchen, kitchenAbout) = pad("A-kitchen", installedAt: 1_700_000_000, network: network)
        let (office, officeAbout) = pad("B-office", installedAt: 1_750_000_000, network: network)
        kitchenAbout.own = "kitchen names"
        network.connect(kitchen, office)

        // The office hears of a newer kitchen document than the kitchen holds,
        // as after the kitchen lost its ledger. The kitchen never takes it as its own.
        let key = SetupKey(kind: HomePadDocumentKind.make(Self.kind, homePad: "A-kitchen"), owner: .household)
        let stale = SetupDocument(key: key, version: SetupVersion(number: 99, time: 1_900_000_000_000, device: "B-office"),
                                  content: .string("stale kitchen names"))
        kitchen.sync.receive(.documents(SetupDocuments(documents: [stale])), from: "B-office", name: "B-office")
        kitchen.sync.shareLocalChanges()
        network.deliverAll()
        #expect(kitchenAbout.heard["A-kitchen"] == nil)
        #expect(officeAbout.heard == ["A-kitchen": "kitchen names"])
    }

    @Test func kindsNameTheirHomePad() {
        #expect(HomePadDocumentKind.make("smarthome.homeKitDirectory", homePad: "ABC") == "smarthome.homeKitDirectory@ABC")
        let split = HomePadDocumentKind.split("smarthome.homeKitDirectory@ABC")
        #expect(split?.kind == "smarthome.homeKitDirectory")
        #expect(split?.homePad == "ABC")
        #expect(HomePadDocumentKind.split("faces.library") == nil)
        #expect(HomePadDocumentKind.split("@ABC") == nil)
        // An older HomePad reads the key as a household document of a kind it does not know.
        #expect(SetupKey("smarthome.homeKitDirectory@ABC/household")?.owner == .household)
    }
}
