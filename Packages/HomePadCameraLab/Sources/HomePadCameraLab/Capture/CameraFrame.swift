import CoreVideo
import Foundation

/// One video frame from the shared camera feed, always 32BGRA and already
/// rotated upright for the current device orientation.
struct CameraFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let capturedAt: Date
    /// True when the frame came from the simulator's synthetic demo feed.
    let isDemo: Bool

    var width: Int { CVPixelBufferGetWidth(pixelBuffer) }
    var height: Int { CVPixelBufferGetHeight(pixelBuffer) }
}

/// Thread-safe fan-out of frames to every consumer, plus the latest frame.
/// Producers call `deliver` from their capture queue, so consumers must
/// copy what they need and return quickly.
final class FrameHub: @unchecked Sendable {
    typealias Consumer = @Sendable (CameraFrame) -> Void

    private let lock = NSLock()
    private var consumers: [UUID: Consumer] = [:]
    private var latest: CameraFrame?

    @discardableResult
    func addConsumer(_ consumer: @escaping Consumer) -> UUID {
        let id = UUID()
        lock.withLock { consumers[id] = consumer }
        return id
    }

    func removeConsumer(_ id: UUID) {
        lock.withLock { consumers[id] = nil }
    }

    func deliver(_ frame: CameraFrame) {
        let current = lock.withLock { () -> [Consumer] in
            latest = frame
            return Array(consumers.values)
        }
        for consumer in current { consumer(frame) }
    }

    /// The most recent frame, if the feed is running.
    var latestFrame: CameraFrame? { lock.withLock { latest } }

    func reset() { lock.withLock { latest = nil } }

    /// Waits for a frame captured after `date`, polling briefly. Returns nil on timeout.
    func frame(after date: Date, timeout: Duration = .seconds(4)) async -> CameraFrame? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let frame = latestFrame, frame.capturedAt > date { return frame }
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return nil }
        }
        return nil
    }
}
