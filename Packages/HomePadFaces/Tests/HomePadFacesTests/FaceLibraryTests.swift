import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

@MainActor @Suite struct FaceLibraryTests {
    private func makeLibrary() -> (FaceLibrary, SettingsStore, Household) {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "faces.test.\(UUID())")!)
        let household = Household(store: settings)
        return (FaceLibrary(settings: settings, household: household), settings, household)
    }

    @Test func startsWithCuratedFacesAndModularShowing() {
        let (library, _, _) = makeLibrary()
        let list = library.list(for: .household)
        #expect(list.faces.count >= 8)
        #expect(library.current(for: .household).faceID == "faces.modular")
        #expect(Set(list.faces.map(\.id)).count == list.faces.count)
    }

    @Test func makingAFaceCurrentPublishesTheSharedSetting() {
        let (library, settings, _) = makeLibrary()
        let added = library.add(faceID: "faces.digital", to: .household)
        library.makeCurrent(added.id, for: .household)
        #expect(settings[CoreSettings.defaultFaceID] == "faces.digital")
        #expect(library.current(for: .household).id == added.id)
        #expect(library.configuration(forFace: "faces.digital", owner: .household).id == added.id)
    }

    @Test func followsTheSharedSettingWhenSomethingElseChangesIt() {
        let (library, settings, _) = makeLibrary()
        settings[CoreSettings.defaultFaceID] = "faces.flow"
        #expect(library.current(for: .household).faceID == "faces.flow")
    }

    @Test func removingKeepsAtLeastOneFace() {
        let (library, _, _) = makeLibrary()
        for face in library.list(for: .household).faces {
            library.remove(face.id, from: .household)
        }
        #expect(library.list(for: .household).faces.count == 1)
    }

    @Test func membersGetTheirOwnListOnFirstEdit() {
        let (library, _, household) = makeLibrary()
        let member = HouseholdMember(name: "Kyle")
        household.add(member)
        let owner = FaceOwner.member(member.id)
        #expect(!library.hasOwnList(owner))
        #expect(library.list(for: owner) == library.list(for: .household))
        let photos = library.list(for: owner).faces.first { $0.faceID == "faces.photos" }!
        library.makeCurrent(photos.id, for: owner)
        #expect(library.hasOwnList(owner))
        #expect(household.members.first?.preferences[FaceLibrary.memberPreferenceKey]?.stringValue == "faces.photos")
        #expect(library.current(for: .household).faceID == "faces.modular")
    }

    @Test func editsAreSaved() {
        let (library, _, _) = makeLibrary()
        var face = library.list(for: .household).faces.first { $0.faceID == "faces.numerals" }!
        face.values["color"] = FaceColor.coral.rawValue
        library.save(face, for: .household)
        #expect(library.configuration(forFace: "faces.numerals", owner: .household).values["color"] == "coral")
    }
}
