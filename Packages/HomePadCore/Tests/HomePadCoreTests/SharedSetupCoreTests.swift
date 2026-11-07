import Foundation
import Testing
@testable import HomePadCore

/// What Core gives the household's shared setup: the shared part of a person,
/// applying people from another HomePad, a person taking the household's ID,
/// and moving saved values with them.
@MainActor @Suite struct SharedSetupCoreTests {
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test.shared.\(UUID())")!)
    }

    @Test func aSharedPersonLeavesThisIPadsEnrollmentAndCurrentFaceOut() throws {
        let member = HouseholdMember(name: "Kyle", colorHex: "#FF9500", isAdmin: true, hasFaceEnrollment: true,
                                     preferences: ["faceID": "faces.numerals", "assistant.provider": "claude"])
        let shared = SharedMember(member)
        #expect(shared.preferences == ["assistant.provider": "claude"])
        let content = try JSONValue(encoding: shared)
        #expect(content["hasFaceEnrollment"] == nil)
        #expect(try content.decoded(as: SharedMember.self) == shared)

        // Applied on another iPad, it keeps that iPad's own parts.
        let there = HouseholdMember(id: member.id, name: "kyle", hasFaceEnrollment: false, preferences: ["faceID": "faces.photos"])
        let kept = shared.member(keeping: there)
        #expect(kept.name == "Kyle" && kept.isAdmin && kept.colorHex == "#FF9500")
        #expect(kept.hasFaceEnrollment == false)
        #expect(kept.preferences == ["assistant.provider": "claude", "faceID": "faces.photos"])
        #expect(shared.member(keeping: nil).hasFaceEnrollment == false)
    }

    @Test func applyingSharedPeopleAddsAndUpdatesThemPastTheHandAddedLimit() {
        let household = Household(store: makeSettings())
        for index in 0..<Household.maxMembers { household.add(HouseholdMember(name: "Person \(index)")) }
        #expect(!household.add(HouseholdMember(name: "Seventh")))
        let joined = SharedMember(id: UUID(), name: "Seventh", avatar: "🦊", colorHex: "#0A84FF", isAdmin: false)
        household.applyShared(joined)
        #expect(household.members.count == Household.maxMembers + 1)

        var first = household.members[0]
        first.hasFaceEnrollment = true
        household.update(first)
        var renamed = SharedMember(first)
        renamed.name = "Renamed"
        household.applyShared(renamed)
        #expect(household.members[0].name == "Renamed")
        #expect(household.members[0].hasFaceEnrollment)
    }

    @Test func aNewIDMovesDataFirstAndKeepsThePersonInPlace() {
        let household = Household(store: makeSettings())
        let kyle = HouseholdMember(name: "Kyle", isAdmin: true, hasFaceEnrollment: true)
        let sam = HouseholdMember(name: "Sam")
        household.add(kyle)
        household.add(sam)
        household.recognize(kyle.id)
        let householdID = UUID()
        var seen: [(UUID, UUID, Bool)] = []
        household.onMemberIDChange { old, new in
            // Handlers run while the person still has the old ID.
            seen.append((old, new, household.members.contains { $0.id == old }))
        }
        household.changeMemberID(from: kyle.id, to: householdID)
        #expect(seen.count == 1 && seen[0].0 == kyle.id && seen[0].1 == householdID && seen[0].2)
        #expect(household.members.map(\.id) == [householdID, sam.id])
        #expect(household.members[0].hasFaceEnrollment)
        #expect(household.activeMemberID == nil)

        // Nothing happens for someone unknown or an ID already taken.
        household.changeMemberID(from: UUID(), to: UUID())
        household.changeMemberID(from: sam.id, to: householdID)
        #expect(seen.count == 1)
    }

    @Test func savedValuesMoveToANewName() {
        let settings = makeSettings()
        let old = SettingKey<String?>("shell.homeScreen.old", default: nil)
        let new = SettingKey<String?>("shell.homeScreen.new", default: nil)
        #expect(!settings.contains(old))
        settings[old] = "layout"
        #expect(settings.contains(old))
        #expect(settings.keyNames(withPrefix: "shell.homeScreen.") == ["shell.homeScreen.old"])
        settings.moveValue(fromKeyNamed: old.name, toKeyNamed: new.name)
        #expect(settings[new] == "layout")
        #expect(!settings.contains(old))
        #expect(settings[old] == nil)
    }

    @Test func appStateFollowsAPersonToTheirNewID() {
        let settings = makeSettings()
        let household = Household(store: settings)
        let kyle = HouseholdMember(name: "Kyle")
        household.add(kyle)
        household.recognize(kyle.id)
        let appState = AppStateStore(settings: settings, household: household)
        let mode = AppStateKey("calendar.mode", default: "day", scope: .member)
        appState[mode] = "week"
        let householdID = UUID()
        household.changeMemberID(from: kyle.id, to: householdID)
        household.recognize(householdID)
        #expect(appState[mode] == "week")
    }

    @Test func ownersReadBackFromTheirKeys() {
        let id = UUID()
        #expect(SharedDocumentOwner(key: SharedDocumentOwner.household.key) == .household)
        #expect(SharedDocumentOwner(key: SharedDocumentOwner.member(id).key) == .member(id))
        #expect(SharedDocumentOwner(key: "guest") == nil)
        #expect(SharedDocumentOwner.member(id).memberID == id)
    }
}
