import Foundation
import HomePadCore
import HomePadUI
import UIKit

/// The shell hosts background work (`AppServices.backgroundWork`) on the iPad
/// that shows HomePad: it starts it, reports what the iPad is doing on every
/// kiosk tick, and asks iOS for background launches as HomePad leaves the screen.
@MainActor
enum BackgroundWorkHost {
    /// True on the iPad that runs the shell. The iPhone and Mac companions run
    /// the same modules but never host background work.
    static var hostsBackgroundWork: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && !ProcessInfo.processInfo.isiOSAppOnMac
    }

    /// What the iPad is doing now, for `BackgroundWork.update(_:)`.
    ///
    /// Work waits while an app zooms and right after a touch. A touch's
    /// screen change, the longest thing a tap sets moving, takes
    /// `Theme.Motion.screenDuration`, so a touch counts that long.
    static func environment(kiosk: KioskController, navigator: ShellNavigator, isForeground: Bool, now: Date) -> BackgroundEnvironment {
        let health = kiosk.health
        let touchedJustNow = now.timeIntervalSince(kiosk.lastTouch) < Theme.Motion.screenDuration
        return BackgroundEnvironment(
            isForeground: isForeground,
            display: kiosk.condition,
            isOnPower: health.power == .charging || health.power == .full,
            isInteracting: navigator.zoomAnimator.isActive || touchedJustNow,
            isOverheating: health.isOverheating
        )
    }
}
