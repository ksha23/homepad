import Foundation
import SwiftUI
import Testing
@testable import HomePadPersonal

@Suite struct PhotoAlbumRulesTests {
    let library = PhotoAlbum(id: "lib", title: "Library", kind: .library, count: 1_204, keyPhoto: .library("a"))
    let favorites = PhotoAlbum(id: "fav", title: "Favorites", kind: .favorites, count: 12)
    let emptyFavorites = PhotoAlbum(id: "fav", title: "Favorites", kind: .favorites, count: 0)
    let picked = PhotoAlbum(id: "picked", title: "Selected Photos", kind: .picked, count: 3)
    let family = PhotoAlbum(id: "family", title: "Family Shared", kind: .shared, count: 40)
    let cousins = PhotoAlbum(id: "cousins", title: "Cousins", kind: .shared, count: 9)
    let trips = PhotoAlbum(id: "trips", title: "Summer Trips", kind: .user, count: 6)
    let kids = PhotoAlbum(id: "kids", title: "Kids", kind: .user, count: 20)
    let videosOnly = PhotoAlbum(id: "videos", title: "Videos Only", kind: .user, count: 0)

    @Test func libraryComesFirstThenFavoritesPickedSharedAndAlbums() {
        let arranged = PhotoAlbumRules.arranged([trips, family, favorites, kids, picked, library, cousins])
        #expect(arranged.map(\.id) == ["lib", "fav", "picked", "family", "cousins", "trips", "kids"])
    }

    @Test func emptyAlbumsAreLeftOutButTheLibraryAlwaysShows() {
        let emptyLibrary = PhotoAlbum(id: "lib", title: "Library", kind: .library, count: 0)
        let arranged = PhotoAlbumRules.arranged([emptyFavorites, videosOnly, emptyLibrary, trips])
        #expect(arranged.map(\.id) == ["lib", "trips"])
        #expect(PhotoAlbumRules.hasNoPhotos([emptyLibrary]))
        #expect(!PhotoAlbumRules.hasNoPhotos(arranged))
    }

    @Test func sectionsGroupTheLibraryWithFavoritesAndPickedPhotos() {
        let sections = PhotoAlbumRules.sections([kids, family, library, favorites, picked, videosOnly])
        #expect(sections.library.map(\.id) == ["lib", "fav", "picked"])
        #expect(sections.shared.map(\.id) == ["family"])
        #expect(sections.albums.map(\.id) == ["kids"])
    }

    @Test func slideshowUsesTheChosenSources() {
        let albums = [library, favorites, family, trips, kids]
        let defaults = PhotoAlbumRules.slideshowSources(albums, selection: PhotoSourceSelection())
        #expect(defaults.map(\.id) == ["fav", "family"])

        let chosen = PhotoSourceSelection(includeFavorites: false, includeSharedAlbums: false, albumIDs: ["kids"])
        #expect(PhotoAlbumRules.slideshowSources(albums, selection: chosen).map(\.id) == ["kids"])

        let everything = PhotoSourceSelection(includeLibrary: true)
        #expect(PhotoAlbumRules.slideshowSources(albums, selection: everything).map(\.id) == ["lib", "fav", "family"])
    }

    @Test func slideshowAlwaysIncludesPickedPhotos() {
        let selection = PhotoSourceSelection(includeFavorites: false, includeSharedAlbums: false)
        #expect(PhotoAlbumRules.slideshowSources([library, favorites, picked], selection: selection).map(\.id) == ["picked"])
    }

    @Test func slideshowFallsBackToTheLibraryWhenTheChosenSourcesAreEmpty() {
        // No favorites and no shared albums yet: the widget shows the library instead of nothing.
        #expect(PhotoAlbumRules.slideshowSources([library, emptyFavorites, trips], selection: PhotoSourceSelection()).map(\.id) == ["lib"])
        let emptyLibrary = PhotoAlbum(id: "lib", title: "Library", kind: .library, count: 0)
        #expect(PhotoAlbumRules.slideshowSources([emptyLibrary, emptyFavorites], selection: PhotoSourceSelection()).isEmpty)
    }

    @Test func savedSelectionsFromBeforeTheLibraryOptionStillDecode() throws {
        let saved = #"{"includeFavorites":false,"includeSharedAlbums":true,"albumIDs":["kids"],"pickedPhotoIDs":["p1"]}"#
        let selection = try JSONDecoder().decode(PhotoSourceSelection.self, from: Data(saved.utf8))
        #expect(selection == PhotoSourceSelection(includeLibrary: false, includeFavorites: false, includeSharedAlbums: true,
                                                  albumIDs: ["kids"], pickedPhotoIDs: ["p1"]))
        let roundTrip = try JSONDecoder().decode(PhotoSourceSelection.self, from: JSONEncoder().encode(PhotoSourceSelection(includeLibrary: true)))
        #expect(roundTrip.includeLibrary)
    }

    @Test func countsReadNaturally() {
        #expect(PhotoAlbum.countText(1) == "1 photo")
        #expect(PhotoAlbum.countText(0) == "0 photos")
        #expect(library.countText.hasSuffix(" photos"))
        #expect(PhotoAlbum.countText(6, videos: 1) == "6 photos, 1 video")
        #expect(PhotoAlbum.countText(1, videos: 3) == "1 photo, 3 videos")
        #expect(PhotoAlbum.countText(0, videos: 2) == "2 videos")
    }

    @Test func videoLengthsReadLikePhotos() {
        #expect(VideoDurationBadge.text(for: 42) == "0:42")
        #expect(VideoDurationBadge.text(for: 725.4) == "12:05")
        #expect(VideoDurationBadge.text(for: 3730) == "1:02:10")
    }

    @Test func demoAlbumsHaveTheirPhotosAndStartWithTheLibrary() {
        #expect(DemoPhotos.albums.first?.kind == .library)
        for album in DemoPhotos.albums {
            #expect(DemoPhotos.photos(in: album.id).count == album.count, "\(album.title)")
        }
    }

    @MainActor @Test func albumGridColumnsFollowTheWidth() {
        // 11-inch iPad Pro content width in landscape and portrait.
        let landscape = AlbumGridView.Layout(width: 1082, height: 640, minimumCover: 200)
        let portrait = AlbumGridView.Layout(width: 706, height: 900, minimumCover: 200)
        #expect(landscape.albumColumns == 4)
        #expect(portrait.albumColumns == 3)
        #expect(landscape.libraryColumns(count: 1) == 2)
        #expect(landscape.libraryColumns(count: 3) == 3)
        #expect(portrait.libraryColumns(count: 3) == 2)
        // Larger text makes covers wider, so fewer fit.
        #expect(AlbumGridView.Layout(width: 706, height: 900, minimumCover: 300).albumColumns == 2)
        #expect(AlbumGridView.Layout(width: 300, height: 900, minimumCover: 400).albumColumns == 1)
        // Library covers stay under 40 percent of the height, so albums show below them.
        let short = AlbumGridView.Layout(width: 1082, height: 400, minimumCover: 200)
        let coverWidth = (1082 - 24) / 2.0
        #expect(coverWidth / short.libraryAspect(count: 2) <= 400 * 0.4 + 0.5)
    }

    /// The title shares the header's leading half with the back button, clear of the Now Playing pill.
    @MainActor @Test func longAlbumNamesMoveOutOfTheHeader() {
        #expect(PhotosAppView.titleFitsHeader("Summer Trips", width: 1082, typeSize: .large))
        #expect(!PhotosAppView.titleFitsHeader("Grandma's 80th Birthday at the Lake House", width: 1082, typeSize: .large))
        #expect(!PhotosAppView.titleFitsHeader("Grandma's 80th Birthday at the Lake House", width: 706, typeSize: .large))
        #expect(!PhotosAppView.titleFitsHeader("Summer Trips", width: 300, typeSize: .accessibility3))
    }
}
