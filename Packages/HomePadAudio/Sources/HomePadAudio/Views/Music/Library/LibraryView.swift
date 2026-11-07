import HomePadCore
import HomePadUI
import SwiftUI

/// The Library section: playlists, albums, artists and songs from the music
/// source, chosen with chips. Albums, playlists and artists open their page.
/// Songs play, with Play Next and Play Later in each row's More menu. The
/// chosen kind is kept with the Music app's place (`MusicPlace`).
struct LibraryView: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(\.musicContentWidth) private var width

    private var kind: LibraryKind { media.musicPlace.libraryKind }

    var body: some View {
        @Bindable var place = media.musicPlace
        // Built once per update, for the grid and the empty check alike.
        let state = LibraryContent.state(kind, media)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if media.musicSource == .thisIPad, let library = media.memberMusic.shown {
                    MemberMusicHeader(library: library, title: library.libraryTitle)
                }
                ChoiceChips(LibraryKind.allCases.map { .init(id: $0, title: $0.title, systemImage: $0.systemImage) },
                            selection: $place.libraryKind)
                switch state {
                case .loading:
                    LoadingShelves(count: 2)
                case .empty(let message):
                    EmptyStateView("Nothing Here Yet", message: message, systemImage: kind.systemImage)
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .items(let items):
                    if kind == .songs {
                        songs(items)
                    } else {
                        grid(items)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
        .task(id: "\(kind.rawValue)|\(media.musicSource.rawValue)|\(media.memberMusic.shown?.memberID.uuidString ?? "")") {
            await LibraryContent.load(kind, media)
        }
    }

    /// Tiles about as wide as a shelf's, in the number of columns that comes closest.
    private func grid(_ items: [MusicTileItem]) -> some View {
        let gutter = Theme.Spacing.l
        let columns = max(2, Int(((width + gutter) / (Self.tileWidth + gutter)).rounded()))
        let tileWidth = max(0, (width - CGFloat(columns - 1) * gutter) / CGFloat(columns))
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: gutter, alignment: .top), count: columns),
                         alignment: .leading, spacing: gutter) {
            ForEach(items) { item in
                ArtworkTile(title: item.title, subtitle: item.subtitle, isActive: item.isActive, width: tileWidth, action: item.action) {
                    item.artworkView(cornerRadius: item.isRound ? Theme.Radius.pill : Theme.Radius.card)
                }
                .musicItemContextMenu(item.menu)
                .unavailable(item.unavailableReason)
            }
        }
    }

    /// The width a tile aims for, as in Listen Now's shelves.
    private static let tileWidth: CGFloat = 190

    private func songs(_ items: [MusicTileItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: Theme.Spacing.l)], alignment: .leading,
                  spacing: Theme.Spacing.xs) {
            ForEach(items) { SongRow(item: $0) }
        }
    }
}
