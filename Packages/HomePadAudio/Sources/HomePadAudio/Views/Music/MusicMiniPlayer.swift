import HomePadCore
import HomePadUI
import SwiftUI

/// The Music app's one mini player, as in Apple Music on iPad: a Liquid Glass
/// bar floating at the bottom of the content column, over the content, with the
/// cover, title, artist and where it plays, then previous, play or pause and
/// next. A tap
/// anywhere but its buttons opens the full-screen player, which zooms out of
/// the bar and back into it, so Music is on the same page and scroll position
/// when it closes.
///
/// A swipe left plays the next song and a swipe right the one before, as in
/// Apple Music and CarPlay. The cover and title follow the finger a little and
/// spring back (`MiniPlayerSwipe`), and a swipe is never also a tap. VoiceOver
/// gets Next Track and Previous Track as actions.
///
/// It is sized for someone walking up to the iPad: as tall as a screen's main
/// control, with round control buttons and Title 3 text.
///
/// It shows what Now Playing has, playing or paused. After a restart, and when
/// HomePad recognizes someone, that is their saved place, paused where it
/// stopped, so Play picks up where they left off. With nothing to show it is
/// not there, and it scales and fades in and out as the Now Playing pill does.
struct MusicMiniPlayer: View {
    /// Music's namespace for the player's zoom out of the bar.
    let zoom: Namespace.ID
    static let zoomID = "music.player"
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    @Environment(\.displayCondition) private var condition
    @Environment(\.colorScheme) private var colorScheme
    /// How far a sideways swipe has dragged, while one is under way.
    @State private var swipe: CGFloat = 0

    /// The widest the bar gets: room for about 40 characters of title beside
    /// the cover and the buttons. It is centered in the content column, like
    /// Apple's.
    static let maxWidth: CGFloat = 760
    /// As tall as a screen's main control, with the cover inside its padding.
    static let height = Theme.Size.heroControl
    private static let coverSide = height - Theme.Spacing.s * 2
    private static let swipePolicy = MiniPlayerSwipe.standard

    var body: some View {
        let nowPlaying = media.nowPlaying
        // Playback starts and stops outside any animation, so the bar's
        // transition runs with an animation of its own, as the pill's does.
        ZStack {
            if let nowPlaying {
                bar(nowPlaying)
                    // Floating above the home indicator bar with comfortable breathing room,
                    // aligning with the sidebar's bottom margin.
                    .padding(.bottom, Theme.Spacing.l)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.settle, value: nowPlaying != nil)
        .task(id: nowPlaying?.artworkURL) {
            if let url = nowPlaying?.artworkURL {
                ArtworkWash.prepare(url)
            }
        }
    }

    private func bar(_ nowPlaying: NowPlaying) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button(action: openNowPlaying) {
                HStack(spacing: Theme.Spacing.m) {
                    NowPlayingArtwork(nowPlaying: nowPlaying, cornerRadius: Theme.Radius.thumbnail)
                        .frame(width: Self.coverSide, height: Self.coverSide)
                    details(nowPlaying)
                    Spacer(minLength: 0)
                }
                // The cover and title follow a sideways swipe a little.
                .offset(x: Self.swipePolicy.offset(for: swipe))
                .opacity(Self.swipePolicy.opacity(for: swipe))
                .contentShape(Rectangle())
            }
            // The glass answers the press, as the pill's does.
            .buttonStyle(.plain)
            .accessibilityLabel([nowPlaying.title, nowPlaying.artist].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint("Opens the player")
            .accessibilityActions {
                if media.canSkip {
                    Button("Next Track") { skip(.next) }
                    Button("Previous Track") { skip(.previous) }
                }
            }
            .accessibilityIdentifier("music.miniPlayer")
            // Previous and next stay in place, dimmed, for radio, so nothing moves between tracks.
            symbolButton("backward.fill", label: "Previous", isEnabled: media.canSkip) {
                skip(.previous)
            }
            symbolButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", label: nowPlaying.isPlaying ? "Pause" : "Play") {
                Task { await media.togglePlayPause() }
            }
            symbolButton("forward.fill", label: "Next", isEnabled: media.canSkip) {
                skip(.next)
            }
        }
        // More room before the cover than above it, so its corners stay clear
        // of the capsule's curve.
        .padding(.leading, Theme.Spacing.l)
        .padding(.trailing, Theme.Spacing.xs)
        .frame(height: Self.height)
        .frame(maxWidth: Self.maxWidth)
        // The text grows up to the Huge text size, as headers do, so it stays
        // inside the bar's fixed height.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // A swiped cover slides under the capsule's round end, not out of the glass.
        .clipShape(Capsule())
        // The padding around the buttons opens Now Playing too.
        .contentShape(Capsule())
        .onTapGesture(perform: openNowPlaying)
        // Anywhere on the bar, its buttons too. A drag that starts sideways
        // takes the touch, so it presses nothing. Radio cannot skip, so there
        // the cover and title only follow and spring back.
        .gesture(DirectionalPan(.horizontal, onChanged: followSwipe, onEnded: releaseSwipe))
        // Liquid Glass with a light tint of the page's color: enough that the
        // text reads over a bright cover scrolling under it, little enough that
        // it still looks like glass on Music's page. A heavy tint made a dark
        // blob on the black page. Darker at night, when every cover under it
        // turns bright red.
        .glassEffect(.regular.tint(glassTint).interactive(), in: Capsule())
    }

    /// The title, then the artist and where it plays, or only the artist when
    /// both do not fit. Crossfades between tracks.
    private func details(_ nowPlaying: NowPlaying) -> some View {
        let output = nowPlaying.outputName ?? media.musicOutputName
        return VStack(alignment: .leading, spacing: 2) {
            Text(nowPlaying.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
            ViewThatFits(in: .horizontal) {
                subtitle(artist: nowPlaying.artist, output: output)
                subtitle(artist: nowPlaying.artist, output: nil)
            }
            .font(.body)
        }
        .contentTransition(.opacity)
        .animation(Theme.Motion.standard, value: nowPlaying.title)
    }

    /// Gray, as in Apple's mini player. Plain colors rather than the adaptive
    /// label styles, which turned see-through on the glass over a dark page. An
    /// accent color such as green turned almost black under night mode's red.
    private func subtitle(artist: String?, output: String?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            if let artist {
                Text(artist)
            }
            if let output {
                Label(output, systemImage: "hifispeaker.fill")
            }
        }
        .foregroundStyle(ink.opacity(0.7))
        .lineLimit(1)
    }

    /// White on the dark bar, black on the light one, as in Apple Music.
    private var ink: Color {
        colorScheme == .light ? .black : .white
    }

    /// The page's own color, lightly: dark in Dark (darker at night), light in Light.
    private var glassTint: Color {
        if condition == .night { return .black.opacity(0.6) }
        return colorScheme == .light ? .white.opacity(0.35) : .black.opacity(0.25)
    }

    /// A symbol on the glass, as in Apple's mini player, with a round control's target.
    private func symbolButton(_ symbol: String, label: String, isEnabled: Bool = true,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(ink.opacity(isEnabled ? 1 : 0.35))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Theme.Size.roundControl, height: Theme.Size.roundControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func openNowPlaying() {
        #if os(iOS)
        FPSMonitor.shared.start(name: "MusicPlayer.expand", duration: 1.2)
        #endif
        media.openPlayer()
    }

    /// Plays the next song or the one before. The buttons, the swipe and the
    /// VoiceOver actions all skip through here.
    private func skip(_ direction: MiniPlayerSwipe.Skip) {
        Task {
            switch direction {
            case .next: await media.nextTrack()
            case .previous: await media.previousTrack()
            }
        }
    }

    // MARK: Swiping

    /// Follows the finger, and smoothly takes over a spring back still under way.
    private func followSwipe(_ translation: CGSize) {
        withAnimation(Theme.Motion.follow) { swipe = translation.width }
    }

    /// Skips when the swipe went far or fast enough, then springs back,
    /// carrying on at the finger's speed. A cancelled drag only springs back.
    private func releaseSwipe(translation: CGSize, velocity: CGSize) {
        let policy = Self.swipePolicy
        if media.canSkip, let direction = policy.skip(translation: translation.width, velocity: velocity.width) {
            skip(direction)
        }
        let speed = policy.offsetVelocity(velocity.width, at: swipe)
        let initialVelocity = SwipeDismissPolicy.relativeVelocity(speed, from: policy.offset(for: swipe), to: 0)
        withAnimation(.interpolatingSpring(Theme.Motion.settleSpring, initialVelocity: initialVelocity)) {
            swipe = 0
        }
    }
}
