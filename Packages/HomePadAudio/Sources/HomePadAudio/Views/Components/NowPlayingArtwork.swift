import HomePadCore
import HomePadUI
import MediaPlayer
import MusicKit
import SwiftUI

/// Artwork for whatever plays now: MusicKit or library artwork when the iPad plays,
/// the speaker's picture or a generated cover otherwise. Crossfades between tracks.
struct NowPlayingArtwork: View {
    let nowPlaying: NowPlaying
    var cornerRadius: CGFloat = Theme.Radius.tile
    /// Draws the next track's cover invisibly so it is loaded before a skip. Only
    /// the Now Playing screen does this: every extra cover view makes MusicKit
    /// fetch and encode the image again.
    var prefetchesNext = false
    @Environment(AudioMediaService.self) private var media
    /// The cover on screen, and the one it replaced. The old cover stays underneath
    /// while the new one loads, so a skip crossfades from cover to cover instead of
    /// fading to nothing and back.
    @State private var shown: Cover?
    @State private var outgoing: Cover?
    @State private var isPrefetchReady = false

    /// One cover's sources. The image comes from the item's own player (by its
    /// source), never from which player has focus, so focus changes cannot swap it.
    private struct Cover: Identifiable {
        let id: String
        let artwork: Artwork?
        let libraryArtwork: MPMediaItemArtwork?
        let url: URL?
        let seed: String
    }

    private var current: Cover {
        let isLocal = nowPlaying.source == .appleMusic
        // The cover's address is part of its id, so when a held cover is replaced
        // by the track's real one, the two crossfade.
        return Cover(
            id: "\(nowPlaying.album ?? nowPlaying.title)|\(nowPlaying.artworkURL?.absoluteString ?? "")",
            artwork: isLocal && media.activeKind == .appleMusic ? media.appleMusic.currentArtwork : nil,
            libraryArtwork: isLocal && media.activeKind == .library ? media.libraryPlayer.currentArtwork : nil,
            url: nowPlaying.artworkURL, seed: nowPlaying.album ?? nowPlaying.title
        )
    }

    var body: some View {
        let current = current
        let active = shown ?? current
        ZStack {
            if prefetchesNext, isPrefetchReady, nowPlaying.source == .appleMusic, media.activeKind == .appleMusic, let next = media.appleMusic.nextArtwork {
                // The next track's cover, drawn invisibly at the same size so MusicKit
                // has it loaded when the track changes. Deferred until after opening
                // animation settles to keep the zoom smooth.
                ArtworkView(artwork: next, systemImage: symbol, cornerRadius: cornerRadius)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let outgoing, outgoing.id != active.id {
                artwork(outgoing)
            }
            artwork(active)
                .id(active.id)
                .transition(.opacity)
        }
        .animation(.smooth(duration: 0.6), value: active.id)
        .task {
            guard prefetchesNext else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { isPrefetchReady = true }
        }
        .task(id: current.id) {
            guard let previous = shown else {
                shown = current
                return
            }
            if previous.id != current.id {
                if prefetchesNext { AppleMusicTrace.note("cover id=\(current.id) art=\(AppleMusicTrace.name(current.artwork))") }
                outgoing = previous
                shown = current
                // Long enough for the new cover to load before the old one goes.
                try? await Task.sleep(for: .seconds(3))
                outgoing = nil
            }
        }
    }

    private func artwork(_ cover: Cover) -> some View {
        ArtworkView(artwork: cover.artwork, libraryArtwork: cover.libraryArtwork, url: cover.url,
                    systemImage: symbol, seed: cover.seed, cornerRadius: cornerRadius)
    }

    private var symbol: String {
        switch nowPlaying.source {
        case .radio: "dot.radiowaves.left.and.right"
        case .ambient: "moon.zzz.fill"
        default: "music.note"
        }
    }
}
