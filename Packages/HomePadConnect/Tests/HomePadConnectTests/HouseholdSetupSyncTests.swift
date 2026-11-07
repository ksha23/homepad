import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Two or three HomePads in memory, joined by `SetupNetwork`, sharing their setup.
@MainActor
@Suite struct HouseholdSetupSyncTests {
    private let installedEarly = Date(timeIntervalSince1970: 1_700_000_000)
    private let installedLate = Date(timeIntervalSince1970: 1_750_000_000)

    /// The household's first HomePad with Kyle and Sam, and a HomePad set up
    /// on its own later with its own Kyle and Alex, before they share.
    private struct TwoHomePads {
        let network: SetupNetwork
        let kitchen: TestHomePad
        let office: TestHomePad
        let kyle: UUID
        let sam: UUID
        let officeKyle: UUID
        let alex: UUID
    }

    private func twoHomePads() -> TwoHomePads {
        let network = SetupNetwork()
        let kitchen = TestHomePad("A-kitchen", installedAt: installedEarly, network: network)
        let office = TestHomePad("B-office", installedAt: installedLate, network: network)
        let kyle = kitchen.addPerson("Kyle")
        let sam = kitchen.addPerson("Sam", enrolled: false)
        kitchen.layouts[.member(kyle)] = "kitchen layout for Kyle"
        kitchen.layouts[.household] = "kitchen guest layout"
        let officeKyle = office.addPerson("kyle ")
        let alex = office.addPerson("Alex")
        office.layouts[.member(officeKyle)] = "office layout for Kyle"
        office.layouts[.member(alex)] = "office layout for Alex"
        office.layouts[.household] = "office guest layout"
        office.wallpapers[.member(officeKyle)] = "ocean"
        return TwoHomePads(network: network, kitchen: kitchen, office: office, kyle: kyle, sam: sam,
                         officeKyle: officeKyle, alex: alex)
    }

    private func joined() -> TwoHomePads {
        let home = twoHomePads()
        home.network.connect(home.kitchen, home.office)
        return home
    }

    // MARK: Joining

    @Test func aHomePadThatJoinsTakesTheHouseholdsSetupAndKeepsItsOwnFaceData() {
        let home = joined()
        let kitchen = home.kitchen, office = home.office

        // The same people with the same IDs on both, the household's names winning.
        #expect(Set(kitchen.household.members.map(\.id)) == [home.kyle, home.sam, home.alex])
        #expect(Set(office.household.members.map(\.id)) == [home.kyle, home.sam, home.alex])
        #expect(office.household.members.first { $0.id == home.kyle }?.name == "Kyle")

        // The office's face data for Kyle moved to the household's ID and never left it.
        #expect(office.faceData[home.kyle] == "kyle 's face on B-office")
        #expect(office.faceData[home.officeKyle] == nil)
        #expect(kitchen.faceData[home.alex] == nil)
        #expect(office.person("Kyle")?.hasFaceEnrollment == true)
        #expect(office.person("Sam")?.hasFaceEnrollment == false)
        #expect(kitchen.person("Alex")?.hasFaceEnrollment == false)

        // The household's setup wins where it has one.
        #expect(office.layouts[.member(home.kyle)] == "kitchen layout for Kyle")
        #expect(office.layouts[.household] == "kitchen guest layout")
        // What the household lacked comes from the HomePad that joined.
        #expect(kitchen.layouts[.member(home.alex)] == "office layout for Alex")
        #expect(kitchen.wallpapers[.member(home.kyle)] == "ocean")
        #expect(office.layouts[.member(home.officeKyle)] == nil)

        #expect(kitchen.sync.sharesSetup && office.sync.sharesSetup)
        #expect(kitchen.sync.syncedPeers.map(\.name) == ["B-office"])
        #expect(office.sync.syncedPeers.map(\.name) == ["A-kitchen"])
    }

    @Test func theHomePadThatHostsTheHouseholdKeepsItsSetupOverAnOlderInstall() {
        let network = SetupNetwork()
        let older = TestHomePad("A-old", installedAt: installedEarly, network: network)
        let host = TestHomePad("B-host", installedAt: installedLate, hosts: true, network: network)
        older.layouts[.household] = "older guest layout"
        host.layouts[.household] = "host guest layout"
        network.connect(older, host)
        #expect(older.layouts[.household] == "host guest layout")
        #expect(host.layouts[.household] == "host guest layout")
    }

    @Test func aThirdHomePadJoinsTheSharedSetup() {
        let home = joined()
        let hall = TestHomePad("C-hall", installedAt: installedEarly.addingTimeInterval(-1), network: home.network)
        hall.layouts[.household] = "hall guest layout"
        // Installed first, but the other two already share a setup, which wins.
        home.network.connect(hall, home.kitchen)
        #expect(hall.layouts[.household] == "kitchen guest layout")
        #expect(Set(hall.household.members.map(\.id)) == [home.kyle, home.sam, home.alex])
    }

    // MARK: Changes

    @Test func aChangeReachesTheOtherHomePadOnceAndNothingComesBack() {
        let home = joined()
        home.network.resetCount()
        home.kitchen.clock.advance(60)
        home.kitchen.edit { $0.layouts[.member(home.kyle)] = "Music moved to page 2" }
        #expect(home.office.layouts[.member(home.kyle)] == "Music moved to page 2")
        #expect(home.network.delivered == [.setupDocuments])

        home.network.resetCount()
        home.office.sync.shareLocalChanges()
        home.kitchen.sync.shareLocalChanges()
        home.network.deliverAll()
        #expect(home.network.delivered.isEmpty)
    }

    @Test func peopleChangesSpreadAndKeepEachHomePadsEnrollment() {
        let home = joined()
        home.office.clock.advance(60)
        home.office.edit { pad in
            guard var sam = pad.person("Sam") else { return }
            sam.colorHex = "#FF9500"
            sam.isAdmin = true
            pad.household.update(sam)
        }
        #expect(home.kitchen.person("Sam")?.colorHex == "#FF9500")
        #expect(home.kitchen.person("Sam")?.isAdmin == true)
        #expect(home.kitchen.person("Kyle")?.hasFaceEnrollment == true)
    }

    @Test func aHomePadThatWasOffCatchesUpWhenItReconnects() {
        let home = joined()
        home.network.disconnect(home.kitchen, home.office)
        home.kitchen.clock.advance(60)
        home.kitchen.edit { $0.layouts[.household] = "new guest layout" }
        home.kitchen.edit { $0.household.remove(home.sam) }
        #expect(home.office.layouts[.household] == "kitchen guest layout")

        home.network.connect(home.kitchen, home.office)
        #expect(home.office.layouts[.household] == "new guest layout")
        #expect(home.office.person("Sam") == nil)

        // With nothing new, a session opening trades only hellos.
        home.network.disconnect(home.kitchen, home.office)
        home.network.resetCount()
        home.network.connect(home.kitchen, home.office)
        #expect(home.network.delivered == [.setupHello, .setupHello])
    }

    @Test func editsMadeApartSettleOnTheLaterOneEverywhere() {
        let home = joined()
        home.network.disconnect(home.kitchen, home.office)
        home.kitchen.clock.advance(60)
        home.office.clock.advance(120)
        home.kitchen.edit { $0.layouts[.household] = "kitchen's edit" }
        home.office.edit { $0.layouts[.household] = "office's later edit" }
        home.office.edit { $0.layouts[.member(home.alex)] = nil }
        home.network.connect(home.kitchen, home.office)
        #expect(home.kitchen.layouts[.household] == "office's later edit")
        #expect(home.office.layouts[.household] == "office's later edit")
        // A layout reset to its default is a deletion that spreads.
        #expect(home.kitchen.layouts[.member(home.alex)] == nil)
    }

    @Test func aPhotoWallpaperStaysOnItsHomePad() {
        let home = joined()
        home.network.resetCount()
        home.office.clock.advance(60)
        home.office.edit { $0.wallpapers[.member(home.kyle)] = "photo" }
        #expect(home.kitchen.wallpapers[.member(home.kyle)] == "ocean")
        #expect(home.network.delivered.isEmpty)

        // A choice made later anywhere else still applies.
        home.kitchen.clock.advance(120)
        home.kitchen.edit { $0.wallpapers[.member(home.kyle)] = "dusk" }
        #expect(home.office.wallpapers[.member(home.kyle)] == "dusk")
    }
}
