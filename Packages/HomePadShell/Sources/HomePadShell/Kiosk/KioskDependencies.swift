import Foundation
import HomePadCore
import UIKit

/// Everything `KioskController` reads from the outside world, injectable for tests.
@MainActor
struct KioskDependencies {
    /// The current time.
    var clock: () -> Date
    /// The latest presence reading. Nil reads `services.presence.snapshot` at call time.
    var presence: (() -> PresenceSnapshot)?
    var brightness: any ScreenBrightnessControl
    var health: DeviceHealthMonitor
    /// Turns the system idle timer (Auto-Lock) off or on.
    var setIdleTimerDisabled: (Bool) -> Void
    /// Ramp time when the screen brightens (waking up).
    var brightenDuration: TimeInterval
    /// Ramp time when the screen darkens (dimming, night, sleep).
    var darkenDuration: TimeInterval
    /// Ramp for auto-brightness following the room's light.
    var roomLightDuration: TimeInterval = 4
    /// How often the controller re-evaluates on its own.
    var tickInterval: Duration

    /// The real device.
    static func live() -> KioskDependencies {
        KioskDependencies(
            clock: Date.init,
            presence: nil,
            brightness: SystemScreenBrightness(),
            health: DeviceHealthMonitor(live: true),
            setIdleTimerDisabled: { UIApplication.shared.isIdleTimerDisabled = $0 },
            brightenDuration: 0.6,
            darkenDuration: 3,
            tickInterval: .seconds(1)
        )
    }
}
