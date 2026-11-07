import HomePadCore
import HomePadUI
import SwiftUI

/// What sits at the top center of every screen, like HomeView's Live
/// Activities: the soonest running timer and Now Playing, side by side.
///
/// Each pill scales and fades in and out on its own (`Theme.Motion.settle`).
/// Beside a timer the Now Playing pill steps down a size (`NowPlayingPill.Content`):
/// up close it drops the title, and in apps it is the cover alone, so the pair
/// keeps to the zone headers leave free (`Theme.Size.nowPlayingZone`) and, on a
/// face, to `Theme.Size.faceNowPlayingWidth`.
///
/// The pills are dark with light text in either appearance, like Live
/// Activities in the Dynamic Island, so they read the same over a white page,
/// a wallpaper or a face (`topPillBackground()`).
struct TopPills: View {
    /// The height of both pills up close, on the face and the Home Screen. The
    /// face makes this much room for them, and `Spacing.m` more.
    static let largeHeight: CGFloat = Theme.Size.faceNowPlayingRoom - Theme.Spacing.m

    /// Small, in apps and on a face from across the room.
    let isCompact: Bool
    /// False where the screen shows its timers itself (Timers, cooking mode).
    var showsTimer = true
    /// False inside Music and Now Playing.
    var showsMusic = true
    @Environment(AppServices.self) private var services

    var body: some View {
        let content = TopPillsContent(services: services, showsTimer: showsTimer, showsMusic: showsMusic)
        let hasTimer = content.timer != nil
        let hasMusic = content.nowPlaying != nil
        // Timers and playback change outside any animation, so the pills only
        // move in and out with an animation of their own here.
        HStack(spacing: Theme.Spacing.xs) {
            if let timer = content.timer {
                TimerPill(timer: timer, others: content.otherTimers, isCompact: isCompact)
                    .transition(Self.transition)
            }
            if let nowPlaying = content.nowPlaying {
                NowPlayingPill(nowPlaying: nowPlaying, isCompact: isCompact,
                               content: .content(isCompact: isCompact, besideTimer: hasTimer))
                    .transition(Self.transition)
            }
        }
        .animation(Theme.Motion.settle, value: hasTimer)
        .animation(Theme.Motion.settle, value: hasMusic)
        .environment(\.colorScheme, .dark)
    }

    /// How a pill comes and goes.
    static let transition: AnyTransition = .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
}

/// Which pills show: the timer to show (the soonest running one, else the
/// soonest paused one) and what plays.
@MainActor
struct TopPillsContent {
    let timer: HomeTimer?
    /// The other running or paused timers, counted as "+2".
    let otherTimers: Int
    let nowPlaying: NowPlaying?

    var isEmpty: Bool { timer == nil && nowPlaying == nil }

    init(services: AppServices, showsTimer: Bool = true, showsMusic: Bool = true) {
        let timers = showsTimer ? Self.ordered(services.timers.timers) : []
        timer = timers.first
        otherTimers = max(0, timers.count - 1)
        let playing = services.media.nowPlaying
        nowPlaying = showsMusic && playing?.isPlaying == true ? playing : nil
    }

    /// Running timers first, the one that ends soonest first, then paused ones
    /// by the time they have left. Finished timers ring full screen instead.
    nonisolated static func ordered(_ timers: [HomeTimer], at now: Date = Date()) -> [HomeTimer] {
        timers.filter { $0.status != .finished }.sorted { lhs, rhs in
            if (lhs.status == .running) != (rhs.status == .running) { return lhs.status == .running }
            return lhs.remaining(at: now) < rhs.remaining(at: now)
        }
    }
}

extension View {
    /// The pills' background: the regular material, dark in either appearance,
    /// in a capsule. Not Liquid Glass, whose lensing blurred the capsule's edge.
    func topPillBackground() -> some View {
        background(.regularMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}
