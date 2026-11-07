import HomePadCore
import HomePadUI
import MusicKit
import SwiftUI

/// "Up Next": what plays now and after it, with shuffle and repeat.
/// - This iPad: the queue reorders with the handles, removes with the minus
///   buttons, and clears with Clear. It is saved for the person it belongs to.
/// - A Music Assistant speaker: its current and next items and how many follow
///   (`music_assistant.get_queue` returns no more).
/// - Spotify: its queue, read only, since the Web API cannot reorder it.
struct QueueSheet: View {
    @Environment(AudioMediaService.self) private var media
    @State private var remoteQueue: MAQueue?
    @State private var isLoading = false

    var body: some View {
        // Changes apply as they are made, so the sheet only closes.
        SheetScreen("Up Next") {
            if canEdit, !localItems.isEmpty {
                GlassCapsuleButton("Clear", systemImage: "trash") { Task { await media.clearUpNext() } }
            }
        } content: {
            List {
                if let current = media.nowPlaying {
                    Section {
                        QueueRow(title: current.title, subtitle: current.artist, url: current.artworkURL)
                    } header: {
                        Text("Now Playing")
                    } footer: {
                        if let origin = media.queueOrigin { Text(origin) }
                    }
                }
                if !media.queueAbilities.isDisjoint(with: [.shuffle, .repeat]) {
                    Section { PlaybackModeRow() }
                }
                content
            }
            .environment(\.editMode, .constant(canEdit ? .active : .inactive))
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let queue = remoteQueue {
            if let next = queue.nextItem {
                Section("Up Next") { QueueRow(title: next.title, subtitle: next.subtitle, url: next.mediaItem?.imageURL) }
            }
            Section {
                Text("\(queue.remainingCount) more in the queue on \(queue.name).").foregroundStyle(.secondary)
            }
        } else if media.transportTarget == .spotify {
            spotifyQueue
        } else if isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if localItems.isEmpty {
            Section {
                Text(emptyMessage).foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(localItems) { item in
                    QueueRow(title: item.title, subtitle: item.subtitle, url: item.artworkURL, artwork: item.artwork)
                }
                .onMove(perform: canEdit ? move : nil)
                .onDelete(perform: canEdit ? remove : nil)
            } header: {
                Text("Up Next")
            } footer: {
                if canEdit { Text("Drag to reorder. Add songs with Play Next or Play Later from any album, playlist or song.") }
            }
        }
    }

    @ViewBuilder
    private var spotifyQueue: some View {
        let items = media.spotify.upNext
        Section {
            if items.isEmpty {
                Text("Nothing is queued on Spotify.").foregroundStyle(.secondary)
            }
            ForEach(Array(items.prefix(50).enumerated()), id: \.offset) { _, item in
                QueueRow(title: item.name, subtitle: item.subtitle, url: item.imageURL)
            }
        } header: {
            Text("Up Next on Spotify")
        } footer: {
            Text("Add songs with Play Next. Spotify lets other apps add to its queue but not reorder it.")
        }
    }

    private var localItems: [QueueItem] {
        media.transportTarget == .local ? media.activeSource?.upNext ?? [] : []
    }

    private var canEdit: Bool { media.queueAbilities.contains(.edit) }

    private var emptyMessage: String {
        if media.activeKind == .appleMusic, media.appleMusic.isStationQueue {
            return "A station chooses its own songs as it plays."
        }
        return canEdit ? "Nothing is queued. Add songs with Play Next or Play Later." : "Nothing is queued."
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        Task { await media.moveUpNext(from: offsets, to: destination) }
    }

    private func remove(at offsets: IndexSet) {
        Task { await media.removeUpNext(at: offsets) }
    }

    private func load() async {
        switch media.transportTarget {
        case .remote(let id):
            guard media.musicAssistant.player(id) != nil else { return }
            isLoading = true
            remoteQueue = await media.musicAssistant.queue(for: id)
            isLoading = false
        case .spotify:
            await media.spotify.refreshQueue()
        default:
            break
        }
    }
}

/// One song in Up Next: artwork, title and artist.
private struct QueueRow: View {
    let title: String
    let subtitle: String?
    var url: URL?
    var artwork: Artwork?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ArtworkView(artwork: artwork, url: url, seed: title, cornerRadius: Theme.Radius.thumbnail)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(title).font(.headline).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// Shuffle and repeat as two capsules, lit when on.
struct PlaybackModeRow: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if media.queueAbilities.contains(.shuffle) {
                GlassCapsuleButton("Shuffle", systemImage: "shuffle", size: .regular, isProminent: media.isShuffled, tint: .white) {
                    media.toggleShuffle()
                }
                .accessibilityAddTraits(media.isShuffled ? .isSelected : [])
            }
            if media.queueAbilities.contains(.repeat) {
                GlassCapsuleButton(media.repeatMode.label, systemImage: media.repeatMode.systemImage, size: .regular,
                                   isProminent: media.repeatMode != .off, tint: .white) {
                    media.cycleRepeat()
                }
                .accessibilityAddTraits(media.repeatMode != .off ? .isSelected : [])
            }
        }
        .listRowBackground(Color.clear)
    }
}
