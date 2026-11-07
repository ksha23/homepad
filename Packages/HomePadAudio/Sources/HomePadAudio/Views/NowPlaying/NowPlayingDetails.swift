import HomePadCore
import HomePadUI
import SwiftUI

/// The column beside (or under) the artwork: where it plays, title, artist,
/// scrubber, transport and volume. Text crossfades between tracks, and every part
/// shrinks before it would overflow.
struct NowPlayingDetails: View {
    let nowPlaying: NowPlaying
    let titleSize: CGFloat
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            sourceLine
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(nowPlaying.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text([nowPlaying.artist, nowPlaying.album].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: titleSize * 0.55, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .id(nowPlaying.title)
            .transition(.opacity)
            .layoutPriority(1)
            // The players keep `elapsed` current without announcing each second
            // (remote speakers by the clock, the iPad's players silently), so
            // this reads it once a second while playing. Paused, nothing moves.
            TimelineView(.periodic(from: .now, by: nowPlaying.isPlaying ? 1 : 3600)) { _ in
                let live = media.nowPlaying ?? nowPlaying
                PlaybackScrubber(elapsed: live.elapsed, duration: live.duration, isLive: live.duration == nil) { seconds in
                    Task { await media.seek(to: seconds) }
                }
            }
            transport
            volumeRow
            ElsewhereInTheHouseStrip()
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .animation(.smooth(duration: 0.5), value: nowPlaying.title)
    }

    private var sourceLine: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: media.focus == .local ? "ipad.landscape" : "hifispeaker.fill")
            // Apple's player picks its own speakers, which HomePad cannot see, so no
            // route name: "This iPad · Speaker" was wrong while it played on HomePods.
            Text(sourceText)
                .lineLimit(1)
            if media.remoteTargetID != nil {
                GlassCapsuleButton("Use This iPad", size: .regular) { media.controlThisIPad() }
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// Where it plays. Apple's player picks its own speakers, which HomePad
    /// cannot see, so no route name: "This iPad · Speaker" was wrong while it
    /// played on HomePods.
    private var sourceText: String {
        switch media.focus {
        case .local: media.playsInApplesPlayer ? "This iPad" : "This iPad · \(media.routes.currentRouteName)"
        case .spotify: "Spotify · \(media.currentRouteName)"
        default: media.currentRouteName
        }
    }

    /// Shuffle, previous, play or pause, next and repeat. Shuffle and repeat stay
    /// in place, dimmed, when what plays has neither (radio, a station), so
    /// nothing moves between tracks.
    private var transport: some View {
        HStack(spacing: Theme.Spacing.l) {
            let abilities = media.queueAbilities
            GlassIconButton("shuffle", label: media.isShuffled ? "Shuffle On" : "Shuffle Off", size: Theme.Size.tapTarget,
                            tint: media.isShuffled ? .white : nil) {
                media.toggleShuffle()
            }
            .disabled(!abilities.contains(.shuffle))
            GlassIconButton("backward.fill", label: "Previous", size: Theme.Size.roundControl) {
                Task { await media.previousTrack() }
            }
            .disabled(!media.canSkip)
            GlassIconButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", label: nowPlaying.isPlaying ? "Pause" : "Play",
                            size: Theme.Size.heroControl, tint: .white) {
                Task { await media.togglePlayPause() }
            }
            GlassIconButton("forward.fill", label: "Next", size: Theme.Size.roundControl) {
                Task { await media.nextTrack() }
            }
            .disabled(!media.canSkip)
            GlassIconButton(media.repeatMode.systemImage, label: media.repeatMode.label, size: Theme.Size.tapTarget,
                            tint: media.repeatMode == .off ? nil : .white) {
                media.cycleRepeat()
            }
            .disabled(!abilities.contains(.repeat))
        }
        .frame(maxWidth: .infinity)
    }

    /// The volume of whatever transport controls (`NowPlayingVolumeTarget`), the
    /// same level the Now Playing widget sets.
    private var volumeRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            if media.volumeTarget.showsAirPlayButton {
                AirPlayButton(size: Theme.Size.tapTarget, isGlass: true)
            }
            NowPlayingVolumeSlider()
        }
        .frame(maxWidth: 560)
    }
}

/// Music Assistant speakers that play while this iPad is the source, as small pills.
struct ElsewhereInTheHouseStrip: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        let players = media.elsewhereInTheHouse.filter { media.transportTarget != .remote($0.id) }
        if !players.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader("Elsewhere in the House")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(players) { player in
                            GlassPill("\(player.name): \(player.title ?? "Playing")", systemImage: player.model.systemImage)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}
