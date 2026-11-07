import HomePadUI
import SwiftUI

/// A shelf of artwork tiles that scrolls sideways, built on HomePadUI's `ShelfRow`
/// and `ArtworkTile`. Artist tiles are round.
struct MusicShelf: View {
    let shelf: MusicShelfModel
    var tileWidth: CGFloat = 190

    var body: some View {
        if !shelf.items.isEmpty {
            ShelfRow(shelf.title) {
                ForEach(shelf.items) { item in
                    ArtworkTile(title: item.title, subtitle: item.subtitle, isActive: item.isActive, width: tileWidth,
                                action: item.action) {
                        item.artworkView(cornerRadius: item.isRound ? Theme.Radius.pill : Theme.Radius.card)
                    }
                    .musicItemContextMenu(item.menu)
                    .unavailable(item.unavailableReason)
                }
            }
        }
    }
}

/// Placeholder shelves while a library loads, so the layout does not jump.
struct LoadingShelves: View {
    var count = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(0..<count, id: \.self) { _ in
                ShelfRow("Loading") {
                    ForEach(0..<6, id: \.self) { index in
                        ArtworkTile(title: "Loading", subtitle: "Music", width: 190, action: {}) {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(.primary.opacity(0.08))
                        }
                        .id(index)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}
