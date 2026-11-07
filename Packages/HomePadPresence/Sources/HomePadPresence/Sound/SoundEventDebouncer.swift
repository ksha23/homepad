import Foundation

/// A sound alert that passed debouncing.
struct SoundAlert: Equatable, Sendable {
    var kind: SoundAlertKind
    var confidence: Double
    var time: Date
}

/// Turns noisy per-window classifier hits into clean alerts.
///
/// - A hit counts only above `minimumConfidence`.
/// - A kind fires once it has `requiredHits` hits within `confirmationWindow`.
/// - After firing, the same kind stays quiet for its `cooldown`, so a
///   smoke alarm beeping for a minute alerts once, not sixty times.
/// - Disabled kinds never fire.
struct SoundEventDebouncer: Sendable {
    var minimumConfidence: Double
    var confirmationWindow: TimeInterval = 3
    var enabledKinds: Set<SoundAlertKind>

    private var hits: [SoundAlertKind: [(time: Date, confidence: Double)]] = [:]
    private var lastFired: [SoundAlertKind: Date] = [:]

    init(minimumConfidence: Double, enabledKinds: Set<SoundAlertKind> = Set(SoundAlertKind.allCases)) {
        self.minimumConfidence = minimumConfidence
        self.enabledKinds = enabledKinds
    }

    /// Feeds one classifier result. Returns an alert when one should fire now.
    mutating func process(kind: SoundAlertKind, confidence: Double, at time: Date) -> SoundAlert? {
        guard enabledKinds.contains(kind), confidence >= minimumConfidence else { return nil }
        if let fired = lastFired[kind], time.timeIntervalSince(fired) < kind.cooldown { return nil }

        var recent = (hits[kind] ?? []).filter { time.timeIntervalSince($0.time) <= confirmationWindow }
        recent.append((time, confidence))
        guard recent.count >= kind.requiredHits else {
            hits[kind] = recent
            return nil
        }
        hits[kind] = []
        lastFired[kind] = time
        let best = recent.map(\.confidence).max() ?? confidence
        return SoundAlert(kind: kind, confidence: best, time: time)
    }

    mutating func reset() {
        hits.removeAll()
        lastFired.removeAll()
    }
}
