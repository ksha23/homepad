import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// Whose each device is and who may see it: the pure rules.
@Suite struct FindMyRulesTests {
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
    let sam = HouseholdMember(name: "Sam Rivera")
    let zoe = HouseholdMember(name: "Zoë")

    func device(_ name: String, owner: String? = nil) -> TrackedDevice {
        TrackedDevice(id: "ha:\(name)", name: name, source: .iCloud, lastUpdated: Date(), ownerName: owner)
    }

    func viewer(_ member: HouseholdMember?, unlocked: Bool = true) -> CalendarViewer {
        CalendarViewer(memberID: member?.id, isUnlocked: unlocked, adminIDs: [kyle.id])
    }

    // MARK: Owners

    @Test func ownerComesFromHomeAssistantThenTheDeviceName() {
        let members = [kyle, sam, zoe]
        #expect(FindMyOwnerMatcher.suggestedOwner(of: device("iPhone", owner: "Sam Rivera"), members: members) == sam)
        // First names are enough, in either direction.
        #expect(FindMyOwnerMatcher.suggestedOwner(of: device("iPhone", owner: "Kyle Example"), members: members) == kyle)
        #expect(FindMyOwnerMatcher.suggestedOwner(of: device("Sam\u{2019}s iPad"), members: members) == sam)
        #expect(FindMyOwnerMatcher.suggestedOwner(of: device("Zoe's Watch"), members: members) == zoe)
        #expect(FindMyOwnerMatcher.suggestedOwner(of: device("Living Room iPad"), members: members) == nil)
        #expect(FindMyOwnerMatcher.suggestedOwner(of: device("Grandma's iPhone"), members: members) == nil)
    }

    @Test func aChoiceInSettingsWins() {
        let members = [kyle, sam]
        let kylesPhone = device("Kyle's iPhone")
        #expect(FindMyOwnerMatcher.ownership(of: kylesPhone, choice: nil, members: members) == .member(kyle.id))
        #expect(FindMyOwnerMatcher.ownership(of: kylesPhone, choice: .member(sam.id), members: members) == .member(sam.id))
        #expect(FindMyOwnerMatcher.ownership(of: kylesPhone, choice: .nobody, members: members) == .nobody)
        #expect(FindMyOwnerMatcher.ownership(of: kylesPhone, choice: .hidden, members: members) == .hidden)
        // A chosen member who left the household falls back to matching.
        #expect(FindMyOwnerMatcher.ownership(of: kylesPhone, choice: .member(UUID()), members: members) == .member(kyle.id))
        #expect(FindMyOwnerMatcher.ownership(of: device("Old iPad"), choice: nil, members: members) == .nobody)
    }

    // MARK: Visibility

    @Test func nobodySeesAnythingWithoutRecognition() {
        let policy = FindMyVisibilityPolicy(shareWithEveryone: true)
        #expect(!policy.isVisible(.member(sam.id), to: .guest))
        // Picking Sam in the People switcher is not recognition.
        #expect(!policy.isVisible(.member(sam.id), to: viewer(sam, unlocked: false)))
    }

    @Test func eachPersonSeesTheirOwnAndAdminsSeeAll() {
        let policy = FindMyVisibilityPolicy()
        #expect(policy.isVisible(.member(sam.id), to: viewer(sam)))
        #expect(!policy.isVisible(.member(kyle.id), to: viewer(sam)))
        #expect(policy.isVisible(.member(sam.id), to: viewer(kyle)))
        #expect(policy.isVisible(.nobody, to: viewer(kyle)))
        #expect(!policy.isVisible(.nobody, to: viewer(sam)))
    }

    @Test func sharingShowsEveryMembersDevicesButNotNobodys() {
        let policy = FindMyVisibilityPolicy(shareWithEveryone: true)
        #expect(policy.isVisible(.member(kyle.id), to: viewer(sam)))
        #expect(!policy.isVisible(.nobody, to: viewer(sam)))
    }

    @Test func hiddenDevicesNeverShow() {
        #expect(!FindMyVisibilityPolicy(shareWithEveryone: true).isVisible(.hidden, to: viewer(kyle)))
    }

    // MARK: Kinds

    @Test func kindComesFromTheModelThenTheName() {
        #expect(FindMyDeviceKind(model: "iPad16,3", name: "Kitchen") == .iPad)
        #expect(FindMyDeviceKind(model: "Apple Watch Series 11", name: "Kyle's Watch") == .watch)
        #expect(FindMyDeviceKind(model: "MacBook Air", name: "Work") == .laptop)
        #expect(FindMyDeviceKind(model: nil, name: "Jordan's Phone") == .phone)
        #expect(FindMyDeviceKind(model: nil, name: "Car") == .other)
    }
}
