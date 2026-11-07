import HomePadCore
import HomePadUI
import SwiftUI

/// Search results from either source: the top result beside the first songs, then shelves.
struct SearchResultsModel {
    var top: MusicTileItem?
    /// "Artist", "Playlist" and so on, over the top result's title.
    var topKind: String?
    var songs: [MusicTileItem] = []
    var shelves: [MusicShelfModel] = []

    static let empty = SearchResultsModel()
    var isEmpty: Bool { top == nil && songs.isEmpty && shelves.allSatisfy(\.items.isEmpty) }
}

struct SearchResultsView: View {
    let results: SearchResultsModel
    @Environment(\.musicContentWidth) private var width

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            let layout = width >= 980
                ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.l))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.l))
            layout {
                if let top = results.top {
                    TopResultCard(item: top, kind: results.topKind)
                        .frame(maxWidth: width >= 980 ? 420 : .infinity)
                }
                if !results.songs.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        SectionHeader("Songs")
                        ForEach(results.songs.prefix(5)) { SongRow(item: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(results.shelves) { MusicShelf(shelf: $0) }
        }
    }
}

/// The big first result with its kind and a play button. When the item has a
/// page (an artist, album or playlist), tapping the card opens it and Play plays it.
private struct TopResultCard: View {
    let item: MusicTileItem
    let kind: String?

    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Top Result")
                Button(action: item.action) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        item.artworkView(cornerRadius: item.isRound ? Theme.Radius.pill : Theme.Radius.tileControl)
                            .frame(width: 160, height: 160)
                        Text(item.title).font(.title.bold()).lineLimit(2)
                        Text(detail)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.menu.play == nil ? "Play \(item.title)" : "Open \(item.title)")
                HStack(spacing: Theme.Spacing.s) {
                    GlassCapsuleButton("Play", systemImage: "play.fill", isProminent: true, tint: .pink,
                                       action: item.menu.play ?? item.action)
                    if item.menu.playNext != nil || item.menu.shuffle != nil {
                        Menu {
                            MusicItemMenuContent(menu: MusicItemMenu(shuffle: item.menu.shuffle, playNext: item.menu.playNext,
                                                                     playLater: item.menu.playLater, addToLibrary: item.menu.addToLibrary))
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        .buttonStyle(.glassIcon(size: Theme.Size.tapTarget))
                    }
                }
            }
        }
        .frame(height: 380)
    }

    /// "Artist · Apple Music", without repeating the kind when the subtitle already has it.
    private var detail: String {
        guard let subtitle = item.subtitle else { return kind ?? "" }
        guard let kind, !subtitle.hasPrefix(kind) else { return subtitle }
        return "\(kind) · \(subtitle)"
    }
}
