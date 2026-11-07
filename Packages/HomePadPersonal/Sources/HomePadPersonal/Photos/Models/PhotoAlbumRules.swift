import Foundation
import HomePadCore

/// How the Photos app orders and groups albums, and which albums feed the
/// slideshow and the Photo widget. Pure, so it is tested without PhotoKit.
enum PhotoAlbumRules {
    /// The groups the Photos app draws, top to bottom.
    struct Sections: Equatable {
        /// The library, Favorites and the photos picked by hand.
        var library: [PhotoAlbum] = []
        var shared: [PhotoAlbum] = []
        var albums: [PhotoAlbum] = []
    }

    /// The library first, then Favorites, picked photos, shared albums and the
    /// household's own albums. Albums with no photos are left out, except the
    /// library, so the main album always shows. Each kind keeps PhotoKit's order.
    static func arranged(_ albums: [PhotoAlbum]) -> [PhotoAlbum] {
        albums.enumerated()
            .filter { $0.element.kind == .library || $0.element.count > 0 }
            .sorted { lhs, rhs in
                let left = rank(lhs.element.kind), right = rank(rhs.element.kind)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    static func sections(_ albums: [PhotoAlbum]) -> Sections {
        var sections = Sections()
        for album in arranged(albums) {
            switch album.kind {
            case .library, .favorites, .picked: sections.library.append(album)
            case .shared: sections.shared.append(album)
            case .user, .demo: sections.albums.append(album)
            }
        }
        return sections
    }

    /// True when no album has a photo, so the app shows its empty state.
    static func hasNoPhotos(_ albums: [PhotoAlbum]) -> Bool {
        albums.allSatisfy { $0.count == 0 }
    }

    /// The albums the person at the screen may see: everything for the
    /// library's owner, shared albums for another recognized member, nothing
    /// for a guest.
    static func visible(_ albums: [PhotoAlbum], to access: PhotoAccessPolicy) -> [PhotoAlbum] {
        albums.filter { access.allows($0.source) }
    }

    /// The albums behind the slideshow and the Photo widget: the sources chosen
    /// in Settings plus any photos picked by hand. When none of them has a
    /// photo, the library stands in, so the widget shows this iPad's photos
    /// instead of an empty tile.
    ///
    /// The widget and the faces are picture frames and pass no `access`. The
    /// Photos app's Play passes the viewer's, so another member plays only
    /// the shared albums among them, or every shared album when none is chosen.
    static func slideshowSources(_ albums: [PhotoAlbum], selection: PhotoSourceSelection,
                                 access: PhotoAccessPolicy? = nil) -> [PhotoAlbum] {
        let ordered = access.map { visible(arranged(albums), to: $0) } ?? arranged(albums)
        let chosen = ordered.filter { album in
            switch album.kind {
            case .library: selection.includeLibrary
            case .favorites: selection.includeFavorites
            case .shared: selection.includeSharedAlbums
            case .user: selection.albumIDs.contains(album.id)
            case .picked, .demo: true
            }
        }
        if chosen.contains(where: { $0.count > 0 }) { return chosen }
        if let access, !access.allowsLibrary {
            return ordered.filter { $0.kind == .shared && $0.count > 0 }
        }
        return ordered.filter { $0.kind == .library && $0.count > 0 }
    }

    private static func rank(_ kind: PhotoAlbum.Kind) -> Int {
        switch kind {
        case .library: 0
        case .favorites: 1
        case .picked: 2
        case .shared: 3
        case .user: 4
        case .demo: 5
        }
    }
}
