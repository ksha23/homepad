import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// Which albums the Photos app shows to whom, and what its Play plays: the
/// owner sees every album, another recognized member the shared albums only,
/// a guest nothing. The Photo widget's sources are not filtered.
@Suite struct PhotoAccessRulesTests {
    let owner = UUID()
    let member = UUID()
    let library = PhotoAlbum(id: "lib", title: "Library", kind: .library, count: 1_204)
    let favorites = PhotoAlbum(id: "fav", title: "Favorites", kind: .favorites, count: 12)
    let picked = PhotoAlbum(id: "picked", title: "Selected Photos", kind: .picked, count: 3)
    let family = PhotoAlbum(id: "family", title: "Family Shared", kind: .shared, count: 40)
    let trips = PhotoAlbum(id: "trips", title: "Summer Trips", kind: .user, count: 6)
    let demo = PhotoAlbum(id: "demo", title: "Demo", kind: .demo, count: 6)

    private var all: [PhotoAlbum] { [library, favorites, picked, family, trips, demo] }

    private func access(_ viewer: UUID?) -> PhotoAccessPolicy {
        PhotoAccessPolicy(ownerID: owner, viewerID: viewer)
    }

    @Test func eachKindOfAlbumHasASource() {
        #expect(family.source == .sharedAlbums)
        for album in [library, favorites, picked, trips, demo] {
            #expect(album.source == .library)
        }
    }

    @Test func theOwnerSeesEveryAlbum() {
        #expect(PhotoAlbumRules.visible(all, to: access(owner)).map(\.id) == all.map(\.id))
    }

    @Test func anotherMemberSeesSharedAlbumsOnly() {
        #expect(PhotoAlbumRules.visible(all, to: access(member)).map(\.id) == ["family"])
    }

    @Test func aGuestSeesNoAlbums() {
        #expect(PhotoAlbumRules.visible(all, to: access(nil)).isEmpty)
    }

    @Test func anotherMembersSlideshowLeavesTheLibraryOut() {
        let selection = PhotoSourceSelection(includeLibrary: true, includeFavorites: true, includeSharedAlbums: true,
                                             albumIDs: ["trips"])
        let sources = PhotoAlbumRules.slideshowSources(all, selection: selection, access: access(member))
        #expect(sources.map(\.id) == ["family"])
        // With no shared album chosen, every shared album stands in, never the library.
        let none = PhotoSourceSelection(includeLibrary: false, includeFavorites: true, includeSharedAlbums: false)
        #expect(PhotoAlbumRules.slideshowSources([library, favorites, family], selection: none, access: access(member)).map(\.id) == ["family"])
    }

    @Test func theWidgetKeepsItsSourcesWhoeverIsThere() {
        let selection = PhotoSourceSelection(includeLibrary: false, includeFavorites: true, includeSharedAlbums: true)
        #expect(PhotoAlbumRules.slideshowSources(all, selection: selection).map(\.id) == ["fav", "picked", "family", "demo"])
        #expect(PhotoAlbumRules.slideshowSources(all, selection: selection, access: access(owner)).map(\.id)
            == ["fav", "picked", "family", "demo"])
    }
}
