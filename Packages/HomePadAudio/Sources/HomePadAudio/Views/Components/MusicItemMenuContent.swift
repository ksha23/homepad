import HomePadUI
import SwiftUI

/// The buttons of a `MusicItemMenu`, for a context menu or a "More" menu.
struct MusicItemMenuContent: View {
    let menu: MusicItemMenu

    var body: some View {
        if let play = menu.play {
            Button("Play", systemImage: "play.fill", action: play)
        }
        if let shuffle = menu.shuffle {
            Button("Shuffle", systemImage: "shuffle", action: shuffle)
        }
        if menu.playNext != nil || menu.playLater != nil {
            Section {
                if let playNext = menu.playNext {
                    Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward", action: playNext)
                }
                if let playLater = menu.playLater {
                    Button("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward", action: playLater)
                }
            }
        }
        if let add = menu.addToLibrary {
            Button("Add to Library", systemImage: "plus", action: add)
        }
        if let open = menu.open {
            Button(menu.openTitle, systemImage: menu.openSystemImage, action: open)
        }
    }
}

/// A round "More" button that opens an item's menu, so Play Next and Play
/// Later are a visible tap away and need no touch and hold.
struct MusicItemMoreButton: View {
    let menu: MusicItemMenu
    var title = "More"

    var body: some View {
        Menu {
            MusicItemMenuContent(menu: menu)
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
    }
}

extension View {
    /// Touch and hold shows the item's menu, as on Radio tiles, when it has one.
    @ViewBuilder
    func musicItemContextMenu(_ menu: MusicItemMenu) -> some View {
        if menu.isEmpty {
            self
        } else {
            contextMenu { MusicItemMenuContent(menu: menu) }
        }
    }
}
