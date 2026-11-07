import MediaPlayer
import MusicKit
import SwiftUI

/// One tile in a Music shelf, from any source: Music Assistant, Apple Music, the
/// synced library or the demo. Shelves and grids draw these, so both music sources
/// look the same.
struct MusicTileItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    var artwork: Artwork?
    var libraryArtwork: MPMediaItemArtwork?
    var artworkURL: URL?
    var systemImage = "music.note"
    /// Artists are round, like in Apple Music.
    var isRound = false
    var isActive = false
    /// Play, Play Next, Play Later and the item's page, for its menu.
    var menu = MusicItemMenu()
    /// Why HomePad cannot play it, such as a song someone uploaded to their
    /// own library. The tile then shows dimmed and takes no taps.
    var unavailableReason: String?
    let action: @MainActor () -> Void

    @MainActor
    func artworkView(cornerRadius: CGFloat) -> ArtworkView {
        ArtworkView(artwork: artwork, libraryArtwork: libraryArtwork, url: artworkURL, systemImage: systemImage,
                    seed: title, cornerRadius: cornerRadius)
    }

    /// The same tile with a menu.
    func with(_ menu: MusicItemMenu) -> MusicTileItem {
        var item = self
        item.menu = menu
        return item
    }
}

/// What a tile's or a song row's menu offers besides its main action: play it,
/// add it to Up Next, or open its page.
struct MusicItemMenu {
    var play: (@MainActor () -> Void)?
    var shuffle: (@MainActor () -> Void)?
    var playNext: (@MainActor () -> Void)?
    var playLater: (@MainActor () -> Void)?
    /// Opens a page, such as the song's album or the artist.
    var open: (@MainActor () -> Void)?
    var openTitle = "Show Album"
    var openSystemImage = "square.stack"
    var addToLibrary: (@MainActor () -> Void)?

    var isEmpty: Bool {
        play == nil && shuffle == nil && playNext == nil && playLater == nil && open == nil && addToLibrary == nil
    }
}

extension View {
    /// Dims a tile or row that cannot play, and keeps taps off it. The reason
    /// is in its subtitle, and VoiceOver reads it too.
    func unavailable(_ reason: String?) -> some View {
        opacity(reason == nil ? 1 : 0.45)
            .disabled(reason != nil)
            .accessibilityHint(reason ?? "")
    }
}

/// A titled list of tiles.
struct MusicShelfModel: Identifiable {
    let title: String
    let items: [MusicTileItem]
    var id: String { title }
}
