import HomePadUI
import SwiftUI

/// System chrome over every screen: the timer and Now Playing pills at the top
/// (not on the face) and power or heat warnings at the bottom.
struct SystemChromeLayer: View {
    /// The app on screen shows its running timers itself (cooking mode, from
    /// `ShowsRunningTimersKey`).
    var screenShowsTimers = false
    @Environment(ShellNavigator.self) private var navigator
    @Environment(KioskController.self) private var kiosk

    var body: some View {
        VStack {
            if showsPills {
                TopPills(isCompact: navigator.openAppID != nil, showsTimer: showsTimer, showsMusic: showsMusic)
                    .nightModeAware()
                    .transition(TopPills.transition)
            }
            Spacer(minLength: 0)
            KioskWarnings()
                .padding(.bottom, navigator.isAmbient ? Theme.Spacing.l : 72)
        }
        .padding(.top, Theme.Spacing.s)
        .animation(Theme.Motion.settle, value: navigator.isAmbient)
        .animation(Theme.Motion.settle, value: showsPills)
    }

    /// Not on the face (it draws its own, drifting with it) or the Home Screen
    /// (its header shows them), and not while asleep.
    private var showsPills: Bool {
        !navigator.isAmbient && navigator.screen != .home && kiosk.condition != .sleeping
    }

    /// Not inside the apps that already show playback. Opening or leaving
    /// them moves the pill in or out.
    private var showsMusic: Bool {
        navigator.openAppID != KnownAppID.nowPlaying && navigator.openAppID != KnownAppID.music
    }

    /// Not inside Timers or a screen that shows the timers in its own header.
    private var showsTimer: Bool {
        navigator.openAppID != KnownAppID.timers && !screenShowsTimers
    }
}
