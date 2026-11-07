import Foundation
import HomePadCore

/// Whether system alarms can ring for timers while HomePad is in the background.
public enum TimerAlarmAuthorization: Sendable {
    case notDetermined
    case authorized
    case denied
    /// AlarmKit is missing or turned off in Kitchen settings.
    case unavailable
}

/// Rings timers when the app is not in front. The in-app overlay handles the
/// foreground, so implementations should not ring while HomePad is visible.
@MainActor
public protocol TimerAlarmScheduling: AnyObject {
    var authorization: TimerAlarmAuthorization { get }
    /// Asks for permission. Called lazily, the first time a timer starts.
    func requestAuthorization() async
    /// Schedules (or reschedules) a system alarm for a running timer's end date.
    func schedule(_ timer: HomeTimer)
    /// Removes the system alarm for a timer, silencing it if it is ringing.
    func cancel(_ id: UUID)
    /// True when the system alarm already rang and someone stopped it outside the
    /// app, so the in-app overlay should not ring again.
    func wasDismissedOutsideApp(_ id: UUID) -> Bool
}
