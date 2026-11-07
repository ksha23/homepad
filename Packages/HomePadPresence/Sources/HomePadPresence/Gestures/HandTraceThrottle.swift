import Foundation

/// Thins the hand lines of the presence trace. Hand pose runs on every
/// analyzed frame, ten a second, and each frame's line differed a little, so
/// hand lines made up most of a 400 MB day of tracing. A line is now written
/// when a hand comes into view or leaves it, and otherwise once a second.
/// Open palm gestures are traced on their own line as they happen.
///
/// Times are frame capture times in seconds. Used on the analysis queue only.
struct HandTraceThrottle: Equatable, Sendable {
    /// Seconds between two hand lines while a hand stays in view, or stays away.
    var interval: TimeInterval = 1
    private var lastAt: TimeInterval?
    private var lastHadHand: Bool?

    /// True when the hand of the frame at `time` should get a line.
    mutating func isDue(hasHand: Bool, at time: TimeInterval) -> Bool {
        let changed = hasHand != lastHadHand
        let waited = lastAt.map { time - $0 >= interval } ?? true
        guard changed || waited else { return false }
        lastAt = time
        lastHadHand = hasHand
        return true
    }
}
