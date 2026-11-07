import Foundation

/// A source of presence readings. Exactly one runs at a time, chosen by the
/// duty cycle through `BackendSelector`.
@MainActor
protocol SensingBackend: AnyObject {
    var kind: BackendKind { get }

    /// Starts producing analyses. `deliver` and `failed` run on the main actor.
    func start(
        framesPerSecond: Double,
        deliver: @escaping @MainActor (FrameAnalysis) -> Void,
        failed: @escaping @MainActor (String) -> Void
    )

    /// Changes how many frames per second are analyzed.
    func setFrameRate(_ framesPerSecond: Double)

    func stop()

    /// Stops, then calls `released` once the camera hardware is free for others.
    func stop(released: @escaping @MainActor () -> Void)
}

extension SensingBackend {
    func stop(released: @escaping @MainActor () -> Void) {
        stop()
        released()
    }
}

/// Drops frames that arrive faster than the target rate. Thread-safe, used on
/// the capture queues where sources deliver more frames than we analyze.
final class FrameThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var minimumInterval: TimeInterval
    private var lastAccepted: TimeInterval = -.infinity

    init(framesPerSecond: Double) {
        minimumInterval = 1 / max(framesPerSecond, 0.1)
    }

    func setFrameRate(_ framesPerSecond: Double) {
        lock.withLock { minimumInterval = 1 / max(framesPerSecond, 0.1) }
    }

    /// True when a frame at `time` should be analyzed.
    func accept(_ time: TimeInterval) -> Bool {
        lock.withLock {
            // A small tolerance keeps a 10 fps target from rounding down to 5 fps.
            guard time - lastAccepted >= minimumInterval * 0.85 else { return false }
            lastAccepted = time
            return true
        }
    }
}
