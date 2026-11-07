import Foundation
import HomePadCore

/// Keeps auto-brightness calm. A new target is only adopted when it differs
/// from the current one by more than `deadband` for at least `hold` seconds,
/// or right away when the display condition changes (waking, dimming, night).
/// Big changes, such as room lights switching on, settle faster.
struct BrightnessStabilizer: Equatable {
    var deadband = 0.07
    var hold: TimeInterval = 4
    var bigChange = 0.25
    var bigChangeHold: TimeInterval = 1.5

    private(set) var committed: Double?
    private var committedCondition: DisplayCondition?
    private var pendingSince: Date?

    /// Why the brightness should change, which decides how fast to ramp.
    enum Change: Equatable {
        case none
        case condition(Double)
        case roomLight(Double)
    }

    mutating func update(target: Double, condition: DisplayCondition, now: Date) -> Change {
        guard let current = committed, committedCondition == condition else {
            commit(target, condition)
            return .condition(target)
        }
        let difference = abs(target - current)
        guard difference > deadband else {
            pendingSince = nil
            return .none
        }
        let since = pendingSince ?? now
        pendingSince = since
        let needed = difference >= bigChange ? bigChangeHold : hold
        guard now.timeIntervalSince(since) >= needed else { return .none }
        commit(target, condition)
        return .roomLight(target)
    }

    /// Forget the committed value (after a manual override ends).
    mutating func reset() {
        committed = nil
        committedCondition = nil
        pendingSince = nil
    }

    private mutating func commit(_ target: Double, _ condition: DisplayCondition) {
        committed = target
        committedCondition = condition
        pendingSince = nil
    }
}
