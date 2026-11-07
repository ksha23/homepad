import Foundation
import HomePadCore
@testable import HomePadShell

/// A controllable clock.
@MainActor
final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Screen brightness without a screen.
@MainActor
final class FakeBrightness: ScreenBrightnessControl {
    var brightness: Double

    init(_ brightness: Double = 0.42) {
        self.brightness = brightness
    }
}

/// A `KioskController` wired to fakes: a manual clock, a settable presence
/// snapshot, fake brightness, and instant ramps. The tick loop is effectively
/// off (one hour), so tests drive time with `advance`.
@MainActor
final class KioskHarness {
    let services: AppServices
    let clock: TestClock
    let brightness = FakeBrightness()
    let health = DeviceHealthMonitor(live: false)
    let controller: KioskController
    var presence = PresenceSnapshot.empty
    var idleTimerDisabled: Bool?
    var interactionEndedCount = 0

    /// - Parameter followsSystemBrightness: false (the default here) tests HomePad's own
    ///   brightness levels. The app's default hands active and ambient to iPadOS.
    init(start: Date = TestDates.date(hour: 12), followsSystemBrightness: Bool = false) {
        let defaults = UserDefaults(suiteName: "homepad.shell.tests.\(UUID().uuidString)")!
        services = AppServices(settings: SettingsStore(defaults: defaults))
        services.settings[ShellSettings.followSystemBrightness] = followsSystemBrightness
        clock = TestClock(start)
        var presenceProvider: () -> PresenceSnapshot = { .empty }
        var idleSetter: (Bool) -> Void = { _ in }
        let dependencies = KioskDependencies(
            clock: { [clock] in clock.now },
            presence: { presenceProvider() },
            brightness: brightness,
            health: health,
            setIdleTimerDisabled: { idleSetter($0) },
            brightenDuration: 0,
            darkenDuration: 0,
            tickInterval: .seconds(3600)
        )
        controller = KioskController(services: services, dependencies: dependencies)
        presenceProvider = { [unowned self] in self.presence }
        idleSetter = { [unowned self] in self.idleTimerDisabled = $0 }
        controller.onInteractionEnded = { [unowned self] in self.interactionEndedCount += 1 }
    }

    var condition: DisplayCondition { controller.condition }

    /// Moves time forward and re-evaluates.
    func advance(_ seconds: TimeInterval) {
        clock.now = clock.now.addingTimeInterval(seconds)
        controller.tick()
    }

    /// Someone at a distance bucket, seen right now.
    func someone(_ proximity: ProximityLevel, looking: Bool = false, light: AmbientLight? = nil) -> PresenceSnapshot {
        PresenceSnapshot(isSomeonePresent: true, peopleCount: 1, proximity: proximity, isLookingAtScreen: looking,
                         ambientLight: light, source: .trueDepth, lastActivity: clock.now)
    }
}
