import Foundation
import Testing
@testable import HomePadCore

/// "Owner only, shared albums for all": the owner sees the library, every
/// recognized member sees shared albums and their own iPhone's photos, and a
/// guest sees nothing. Plus who the owner is when nobody chose one.
@Suite struct PhotoAccessPolicyTests {
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
    let sam = HouseholdMember(name: "Sam")
    let alex = HouseholdMember(name: "Alex", isAdmin: true)

    private func policy(viewer: HouseholdMember?) -> PhotoAccessPolicy {
        PhotoAccessPolicy(ownerID: kyle.id, viewerID: viewer?.id)
    }

    @Test func theOwnerSeesEverySourceOfTheirOwn() {
        let access = policy(viewer: kyle)
        #expect(access.allows(.library))
        #expect(access.allows(.sharedAlbums))
        #expect(access.allows(.memberDevice(kyle.id)))
        #expect(access.allowsLibrary)
        #expect(access.allowsAnyPhotos)
    }

    @Test func anotherMemberSeesSharedAlbumsAndTheirOwnPhoneOnly() {
        let access = policy(viewer: sam)
        #expect(!access.allows(.library))
        #expect(access.allows(.sharedAlbums))
        #expect(access.allows(.memberDevice(sam.id)))
        #expect(!access.allows(.memberDevice(kyle.id)))
        #expect(!access.allowsLibrary)
        #expect(access.allowsAnyPhotos)
    }

    @Test func aGuestSeesNothing() {
        let access = policy(viewer: nil)
        #expect(!access.allows(.library))
        #expect(!access.allows(.sharedAlbums))
        #expect(!access.allows(.memberDevice(kyle.id)))
        #expect(!access.allowsAnyPhotos)
    }

    @Test func noOwnerMeansNobodySeesTheLibrary() {
        let access = PhotoAccessPolicy(ownerID: nil, viewerID: sam.id)
        #expect(!access.allows(.library))
        #expect(access.allows(.sharedAlbums))
    }

    @Test func theChosenOwnerWinsWhileTheyAreInTheHousehold() {
        let members = [alex, sam, kyle]
        #expect(PhotoLibraryOwner.resolve(chosen: kyle.id, members: members) == kyle.id)
        #expect(PhotoLibraryOwner.resolve(chosen: sam.id, members: members) == sam.id)
    }

    @Test func withoutAChoiceTheFirstAdminOwnsTheLibrary() {
        #expect(PhotoLibraryOwner.resolve(chosen: nil, members: [sam, alex, kyle]) == alex.id)
        // Someone who left the household no longer owns it.
        #expect(PhotoLibraryOwner.resolve(chosen: UUID(), members: [sam, kyle]) == kyle.id)
        // No admin at all: the first member.
        #expect(PhotoLibraryOwner.resolve(chosen: nil, members: [sam]) == sam.id)
        #expect(PhotoLibraryOwner.resolve(chosen: nil, members: []) == nil)
    }

    @Test func backgroundWorkReadsOnlyWhatSomeMemberMaySee() {
        #expect(PhotoAccessPolicy.householdSources(ownerID: kyle.id) == [.library, .sharedAlbums])
        #expect(PhotoAccessPolicy.householdSources(ownerID: nil).isEmpty)
    }

    @MainActor @Test func theServicesFollowRecognitionNotAPickByHand() {
        let defaults = UserDefaults(suiteName: "PhotoAccessPolicyTests.\(UUID().uuidString)")!
        let services = AppServices(settings: SettingsStore(defaults: defaults), backgroundWork: BackgroundWork(recordsURL: nil))
        services.household.add(kyle)
        services.household.add(sam)
        #expect(services.photoLibraryOwnerID == kyle.id)
        services.household.select(kyle.id)
        #expect(!services.photoAccess.allowsLibrary)
        services.household.recognize(kyle.id)
        #expect(services.photoAccess.allowsLibrary)
        services.household.recognize(sam.id)
        #expect(!services.photoAccess.allowsLibrary)
        #expect(services.photoAccess.allows(.sharedAlbums))
        services.settings[PhotoLibraryOwner.setting] = sam.id
        #expect(services.photoAccess.allowsLibrary)
    }
}
