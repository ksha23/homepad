import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// What the Photos app shows of the recognized person's own iPhone.
@MainActor
@Suite struct PhoneLibraryVisibilityTests {
    let kyle = UUID()
    let sam = UUID()
    let cover = PhonePhoto(id: "p1", pixelWidth: 4032, pixelHeight: 3024)

    private func library(albums: [PhoneAlbum]? = nil) -> PhoneLibrary {
        PhoneLibrary(memberID: kyle, deviceName: "Kyle's iPhone", albums: albums ?? [
            PhoneAlbum(id: "phone.recents", title: "Recents", kind: .recents, count: 30, keyPhoto: cover),
            PhoneAlbum(id: "phone.favorites", title: "Favorites", kind: .favorites, count: 8),
            PhoneAlbum(id: "lake", title: "Lake Weekend", kind: .album, count: 9),
            PhoneAlbum(id: "empty", title: "Empty", kind: .album, count: 0),
        ], isConnected: false)
    }

    @Test func onlyTheRecognizedOwnerSeesTheirPhone() {
        #expect(PhoneLibraryVisibility.shown(library(), unlockedMember: kyle) != nil)
        #expect(PhoneLibraryVisibility.shown(library(), unlockedMember: sam) == nil, "another member")
        #expect(PhoneLibraryVisibility.shown(library(), unlockedMember: nil) == nil, "a guest, or Kyle only picked in People")
        #expect(PhoneLibraryVisibility.shown(nil, unlockedMember: kyle) == nil, "the phone has not answered")
        let empty = library(albums: [PhoneAlbum(id: "phone.recents", title: "Recents", kind: .recents, count: 0)])
        #expect(PhoneLibraryVisibility.shown(empty, unlockedMember: kyle) == nil, "nothing to show")
    }

    @Test func theAccessRuleHasTheLastWord() {
        struct Nobody: PhoneLibraryAccess {
            func mayShowPhoneLibrary(of owner: UUID, to viewer: UUID?) -> Bool { false }
        }
        #expect(PhoneLibraryVisibility.shown(library(), unlockedMember: kyle, access: Nobody()) == nil)
    }

    /// The Photos access rule gives a phone to its own member alone, whoever owns the iPad's library.
    @Test func thePhotoAccessPolicyGivesAPhoneToItsMemberAlone() {
        let policy = PhotoAccessPolicy(ownerID: sam, viewerID: kyle)
        #expect(PhoneLibraryVisibility.shown(library(), unlockedMember: kyle, access: policy) != nil)
        let samAtTheScreen = PhotoAccessPolicy(ownerID: sam, viewerID: sam)
        #expect(PhoneLibraryVisibility.shown(library(), unlockedMember: sam, access: samAtTheScreen) == nil)
    }

    @Test func theSectionListsRecentsAndFavoritesThenAlbums() {
        var opened: PhoneAlbum?
        let section = PhoneLibraryVisibility.section(library()) { opened = $0 }
        #expect(section.title == "From Kyle's iPhone")
        #expect(section.albumsTitle == "Albums on Kyle's iPhone")
        #expect(section.library.map(\.title) == ["Recents", "Favorites"])
        #expect(section.albums.map(\.title) == ["Lake Weekend"], "empty albums are left out")
        #expect(section.library.first?.keyPhoto == .phone(cover))
        section.onOpen(section.albums[0])
        #expect(opened?.id == "lake")
    }
}
