import Foundation

/// Decides frame by frame when the analyzer takes a recognition sample.
///
/// On TrueDepth iPads every sample needs depth for its liveness check, but
/// depth arrives on only some frames, and not at all on the first frames after
/// face tracking starts. A sample taken without depth used to be skipped, which
/// lost a whole sampling interval. Now a due sample waits for the next frame
/// that has depth, usually one frame later. If depth stays away for
/// `maxDepthWait`, the sample goes ahead without it and the recognition service
/// decides (a recent live check covers it, or it is skipped).
///
/// Times are frame capture times in seconds. Used on the analysis queue only.
struct RecognitionSampleGate: Equatable, Sendable {
    /// Longest a due sample waits for a frame with depth.
    var maxDepthWait: TimeInterval = 0.5
    /// Share of the interval that must have passed. Frames come at a fixed rate
    /// with some jitter, so a 0.2 s interval at 10 fps would otherwise often
    /// miss the frame 0.2 s later and wait for the one after it.
    static let tolerance = 0.85

    private(set) var lastSampleTime: TimeInterval = -.infinity
    private var depthWaitStart: TimeInterval?

    /// True when the frame at `time` should be sampled.
    /// - Parameters:
    ///   - wanted: recognition wants a sample and the face is within range.
    ///   - interval: seconds wanted between samples (`RecognitionCadence`).
    ///   - hasDepth: the frame has fresh depth for the liveness check.
    ///   - needsDepth: samples from this frame's camera need depth.
    mutating func shouldSample(
        at time: TimeInterval, wanted: Bool, interval: TimeInterval, hasDepth: Bool, needsDepth: Bool
    ) -> Bool {
        guard wanted else {
            depthWaitStart = nil
            return false
        }
        guard time - lastSampleTime >= interval * Self.tolerance else { return false }
        guard needsDepth else {
            depthWaitStart = nil
            return true
        }
        // The wait counts from the first due frame, even when a frame with depth
        // came in between but had no face to sample.
        let start = depthWaitStart ?? time
        depthWaitStart = start
        return hasDepth || time - start >= maxDepthWait
    }

    /// Records that a sample was taken at `time` (a face was found and embedded).
    /// Returns how long the sample waited for depth, or nil if it did not wait.
    @discardableResult
    mutating func recordSample(at time: TimeInterval) -> TimeInterval? {
        let waited = depthWaitStart.map { time - $0 }
        lastSampleTime = time
        depthWaitStart = nil
        return waited.flatMap { $0 > 0 ? $0 : nil }
    }
}
