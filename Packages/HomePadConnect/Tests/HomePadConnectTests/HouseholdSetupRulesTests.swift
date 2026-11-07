import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

@Suite struct SetupVersionTests {
    @Test func aChangeIsLaterThanWhatItReplacedEvenWithAClockBehind() {
        let previous = SetupVersion(number: 3, time: 2_000_000, device: "B")
        let next = SetupVersion.next(after: previous, device: "A", now: Date(timeIntervalSince1970: 1))
        #expect(next > previous)
        #expect(next.number == 4)
        #expect(next.time == 2_000_001)
        #expect(next.device == "A")
    }

    @Test func laterTimeWinsThenTheNumberThenTheDevice() {
        let early = SetupVersion(number: 9, time: 100, device: "Z")
        let late = SetupVersion(number: 1, time: 200, device: "A")
        #expect(late > early)
        #expect(SetupVersion(number: 2, time: 100, device: "A") > SetupVersion(number: 1, time: 100, device: "Z"))
        #expect(SetupVersion(number: 1, time: 100, device: "B") > SetupVersion(number: 1, time: 100, device: "A"))
    }

    @Test func aVersionReadsBackExactly() throws {
        let version = SetupVersion.next(after: nil, device: "pad", now: Date(timeIntervalSince1970: 1_800_000_000.123_456))
        let data = try PeerCoding.encoder().encode(version)
        #expect(try PeerCoding.decoder().decode(SetupVersion.self, from: data) == version)
        #expect(version.time == 1_800_000_000_123)
    }
}

@Suite struct SetupMergeTests {
    private let key = SetupKey(kind: "shell.homeScreen", owner: .household)

    private func document(_ text: String?, at time: Int64, by device: String = "A", key: SetupKey? = nil) -> SetupDocument {
        SetupDocument(key: key ?? self.key, version: SetupVersion(number: 1, time: time, device: device),
                      content: text.map(JSONValue.string))
    }

    @Test func theNewerVersionWinsInEitherOrder() {
        let old = document("old", at: 1)
        let new = document("new", at: 2, by: "B")
        #expect(SetupMerge.winner(old, new) == new)
        #expect(SetupMerge.winner(new, old) == new)
    }

    @Test func aNewerDeletionWinsAndAnEditAfterItRevives() {
        let live = document("layout", at: 1)
        let deleted = document(nil, at: 2, by: "B")
        #expect(SetupMerge.winner(live, deleted).isDeleted)
        let revived = document("again", at: 3)
        #expect(SetupMerge.winner(deleted, revived).content == "again")
    }

    @Test func theMergeIsCommutativeAssociativeAndIdempotent() {
        let other = SetupKey.member(UUID())
        let a = [document("a", at: 1), document("a person", at: 5, key: other)]
        let b = [document("b", at: 2, by: "B")]
        let c = [document(nil, at: 3, by: "C"), document("c person", at: 4, by: "C", key: other)]
        func merged(_ sets: [[SetupDocument]]) -> [SetupKey: SetupDocument] {
            sets.reduce([:]) { SetupMerge.merge($0, $1) }
        }
        #expect(merged([a, b]) == merged([b, a]))
        #expect(merged([a, b, c]) == merged([c, b, a]))
        #expect(merged([a, a]) == merged([a]))
        #expect(merged([a, b, c])[key]?.isDeleted == true)
        #expect(merged([a, b, c])[other]?.content == "a person")
    }

    @Test func aHelloIsAnsweredWithWhatTheOtherLacksOrHoldsOlder() {
        let shared = document("same", at: 1)
        let mine = document("mine", at: 9, key: SetupKey(kind: "faces.library", owner: .household))
        let older = document("newer here", at: 7, key: SetupKey(kind: "shell.wallpaper", owner: .household))
        let theirNewer = document("newer there", at: 3, key: SetupKey(kind: "faces.rotation", owner: .household))
        let local = [shared.key: shared, mine.key: mine, older.key: older, theirNewer.key: theirNewer]
        let manifest: [SetupKey: SetupVersion] = [
            shared.key: shared.version,
            older.key: SetupVersion(number: 1, time: 2, device: "B"),
            theirNewer.key: SetupVersion(number: 1, time: 5, device: "B"),
        ]
        #expect(SetupMerge.newer(in: local, than: manifest) == [mine, older])
    }
}

@Suite struct SetupEncodingTests {
    @Test func keysReadBack() {
        let id = UUID()
        #expect(SetupKey("shell.homeScreen/household") == SetupKey(kind: "shell.homeScreen", owner: .household))
        #expect(SetupKey("core.member/\(id.uuidString)") == .member(id))
        #expect(SetupKey("no owner") == nil)
        #expect(SetupKey("faces.library/someone") == nil)
    }

    @Test func messagesCrossTheWireIntact() throws {
        let key = SetupKey(kind: "shell.homeScreen", owner: .member(UUID()))
        let version = SetupVersion(number: 2, time: 1_800_000_000_000, device: "A")
        let set = SetupDocuments(documents: [
            SetupDocument(key: key, version: version, content: ["pages": [["kind": "app", "targetID": "music"]]]),
            SetupDocument(key: .member(UUID()), version: version, content: nil),
        ], isComplete: true, standing: SetupStanding(sharesSetup: true, hostsHousehold: false, installedAt: 7, deviceID: "A"))
        let hello = SetupHello(householdID: "h", standing: SetupStanding(sharesSetup: false, hostsHousehold: true,
                                                                       installedAt: 1, deviceID: "B"),
                               manifest: [key.description: version])
        for message in [SetupMessage.documents(set), .hello(hello)] {
            let wire = try MessageCodec.decode(MessageCodec.encode(message.peerMessage(sender: "A")))
            #expect(SetupMessage(wire) == message)
        }
        #expect(hello.versions == [key: version])
        // A deletion stays a deletion after the wire.
        let wire = try MessageCodec.decode(MessageCodec.encode(SetupMessage.documents(set).peerMessage(sender: "A")))
        guard case .documents(let received)? = SetupMessage(wire) else {
            Issue.record("The documents did not read back")
            return
        }
        #expect(received.documents[1].isDeleted)
        #expect(SetupMessage(PeerMessage(type: .boardSync, sender: "A")) == nil)
    }

    @Test func theLedgerReadsBack() throws {
        var ledger = SetupLedger()
        let key = SetupKey(kind: "faces.library", owner: .household)
        ledger.documents[key] = SetupDocument(key: key, version: SetupVersion(number: 1, time: 5, device: "A"),
                                              content: ["currentID": "x"])
        ledger.householdID = "h"
        ledger.peers["B"] = SetupPeer(name: "Office", lastSync: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try PeerCoding.encoder().encode(ledger)
        #expect(try PeerCoding.decoder().decode(SetupLedger.self, from: data) == ledger)
    }
}

@Suite struct SetupJoinPlanTests {
    private func shared(_ name: String, id: UUID = UUID()) -> SharedMember {
        SharedMember(id: id, name: name, avatar: "🙂", colorHex: "#0A84FF", isAdmin: false)
    }

    @Test func namesMatchIgnoringCaseAccentsAndSpacing() {
        let local = [HouseholdMember(name: "  kyle "), HouseholdMember(name: "Zoë  Li"), HouseholdMember(name: "Alex")]
        let household = [shared("Kyle"), shared("zoe li"), shared("Sam")]
        let plan = SetupJoinPlan.make(local: local, household: household)
        #expect(plan.matches == [.init(local: local[0].id, household: household[0].id),
                                 .init(local: local[1].id, household: household[1].id)])
        #expect(plan.newcomers == [local[2].id])
    }

    @Test func eachOfTheHouseholdsPeopleMatchesOnce() {
        let local = [HouseholdMember(name: "Sam"), HouseholdMember(name: "Sam")]
        let household = [shared("Sam")]
        let plan = SetupJoinPlan.make(local: local, household: household)
        #expect(plan.matches.map(\.local) == [local[0].id])
        #expect(plan.newcomers == [local[1].id])
    }

    @Test func someoneWithTheHouseholdsIDNeedsNoMatch() {
        let id = UUID()
        let local = [HouseholdMember(id: id, name: "Renamed Here")]
        let plan = SetupJoinPlan.make(local: local, household: [shared("Kyle", id: id), shared("Renamed Here")])
        #expect(plan.matches.isEmpty)
        #expect(plan.newcomers.isEmpty)
    }
}

@Suite struct SetupStandingTests {
    private func standing(shares: Bool = false, hosts: Bool = false, installed: Int64 = 100, device: String = "M") -> SetupStanding {
        SetupStanding(sharesSetup: shares, hostsHousehold: hosts, installedAt: installed, deviceID: device)
    }

    @Test func sharingBeatsHostingBeatsInstallingFirstBeatsTheLowerID() {
        #expect(standing(installed: 1, device: "A") < standing(shares: true, installed: 999, device: "Z"))
        #expect(standing(installed: 1, device: "A") < standing(hosts: true, installed: 999, device: "Z"))
        #expect(standing(installed: 999, device: "A") < standing(installed: 1, device: "Z"))
        #expect(standing(device: "Z") < standing(device: "A"))
        #expect(!(standing() < standing()))
    }
}
