import HomePadCore
import HomePadUI
import SwiftUI

/// A Dynamic Island style capsule at the top while music plays, so playback
/// stays one tap away from any screen. Tapping opens Now Playing (or Music).
/// `TopPills` places it and decides how much it shows: the title up close,
/// the cover and bars in apps, and the cover alone beside a timer in apps.
struct NowPlayingPill: View {
    /// What the pill shows besides the cover.
    enum Content: Equatable {
        /// The title, the artist and the bars.
        case titles
        /// The bars.
        case bars
        /// Nothing: a circle with the cover.
        case cover

        /// Steps down a size beside the timer pill, so the pair keeps to the
        /// zone headers leave free.
        static func content(isCompact: Bool, besideTimer: Bool) -> Content {
            switch (isCompact, besideTimer) {
            case (false, false): .titles
            case (true, false), (false, true): .bars
            case (true, true): .cover
            }
        }
    }

    let nowPlaying: NowPlaying
    /// As tall as `minTapTarget` with a smaller cover, else `TopPills.largeHeight`.
    let isCompact: Bool
    let content: Content
    @Environment(ModuleRegistry.self) private var registry
    @Environment(ShellNavigator.self) private var navigator

    var body: some View {
        let height = isCompact ? Theme.Size.minTapTarget : TopPills.largeHeight
        Button(action: open) {
            HStack(spacing: content == .bars ? Theme.Spacing.l : Theme.Spacing.s) {
                artwork
                if content == .titles {
                    VStack(alignment: .leading, spacing: 0) {
                        // White, not the adaptive primary style: on Liquid Glass that
                        // flips dark or light by its own reading of what is behind the
                        // pill, and turned black over dark screens until a press reset
                        // it. The pill's glass is tinted dark, so white always reads.
                        Text(nowPlaying.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        if let artist = nowPlaying.artist {
                            // A plain gray: the adaptive secondary style takes on
                            // the colors behind the glass and was hard to read on
                            // some wallpapers and pages.
                            Text(artist).font(.caption).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: 260, alignment: .leading)
                    .transition(.opacity)
                }
                if content != .cover {
                    LiveWaveform(isPlaying: nowPlaying.isPlaying, tint: .accentColor)
                        .transition(.opacity)
                }
            }
            .padding(.leading, Theme.Spacing.xs)
            .padding(.trailing, content == .cover ? Theme.Spacing.xs : Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
            // The cover alone is a circle as tall as the pill.
            .frame(minWidth: content == .cover ? height : nil, minHeight: height)
        }
        .buttonStyle(.plain)
        .topPillBackground()
        // Music opened from the pill closes back into it.
        .zoomSource(ZoomSourceID.pill(KnownAppID.nowPlaying), shape: .capsule)
        .accessibilityLabel("Now playing: \(nowPlaying.title)\(nowPlaying.artist.map { " by \($0)" } ?? "")")
        .accessibilityHint("Opens Now Playing")
    }

    /// The same cover the Now Playing widget shows, from the module that
    /// plays. Loading `artworkURL` here showed a music note whenever the cover
    /// came from Apple Music or the library, which have no address.
    private var artwork: some View {
        let side: CGFloat = isCompact ? 30 : 40
        return Group {
            if let cover = registry.nowPlayingArtwork {
                cover(nowPlaying, side / 2)
            } else {
                Image(systemName: "music.note")
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.pink.gradient)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }

    private func open() {
        navigator.openNowPlaying()
    }
}
