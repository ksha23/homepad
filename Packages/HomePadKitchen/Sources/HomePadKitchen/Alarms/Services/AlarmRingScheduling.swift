import Foundation

/// Rings wake-up alarms when HomePad is not in front, the way
/// `TimerAlarmScheduling` does for timers. The in-app alert rings in the
/// foreground, so each alarm's system copy is set a moment after the in-app one.
@MainActor
public protocol AlarmRingScheduling: AnyObject {
    /// Sets (or moves) the system alarm for the alarm's next ring.
    func schedule(_ alarm: HomeAlarm, at date: Date)
    /// Removes the system alarm, silencing it if it rings.
    func cancel(_ id: UUID)
    /// True when the system alarm already rang and someone stopped it outside
    /// the app, so the in-app alert should not ring again.
    func wasDismissedOutsideApp(_ id: UUID) -> Bool
}

/// Rings nothing, for tests and for when background alarms are off.
@MainActor
final class NoAlarmRings: AlarmRingScheduling {
    func schedule(_ alarm: HomeAlarm, at date: Date) {}
    func cancel(_ id: UUID) {}
    func wasDismissedOutsideApp(_ id: UUID) -> Bool { false }
}
