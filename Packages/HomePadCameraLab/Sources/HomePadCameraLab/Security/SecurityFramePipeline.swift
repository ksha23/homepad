import CoreGraphics
import Foundation

/// Per-frame work for Security Camera mode. Runs on the camera's queue:
/// feeds the MJPEG server, runs motion detection five times a second, and
/// confirms motion with person detection before raising an alert.
final class SecurityFramePipeline: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        var sensitivity: MotionSensitivity
        var requirePerson: Bool
        /// Minimum seconds between alerts.
        var cooldown: TimeInterval = 30
        /// Frames per second sent to stream viewers.
        var streamFPS: Double = 6
    }

    /// A confirmed motion event, with a snapshot.
    struct Alert: Sendable {
        let jpeg: Data
        let personDetected: Bool
        let changedFraction: Double
    }

    static let analysisInterval: TimeInterval = 0.2
    /// With nobody watching, one frame a second keeps `/snapshot.jpg` fresh.
    static let idlePublishInterval: TimeInterval = 1
    static let confirmInterval: TimeInterval = 1
    static let streamMaxDimension: CGFloat = 1280
    static let snapshotMaxDimension: CGFloat = 1600

    private let lock = NSLock()
    private var configuration: Configuration
    private var detector: MotionDetector
    private var lastAnalysis = Date.distantPast
    private var lastPublish = Date.distantPast
    private var lastAlert = Date.distantPast
    private var lastConfirmAttempt = Date.distantPast
    private var isConfirming = false

    private let server: MJPEGServer
    private let onAlert: @Sendable (Alert) -> Void
    private let onMotionLevel: @Sendable (Double) -> Void

    init(configuration: Configuration, server: MJPEGServer,
         onAlert: @escaping @Sendable (Alert) -> Void, onMotionLevel: @escaping @Sendable (Double) -> Void) {
        self.configuration = configuration
        self.detector = MotionDetector(configuration: configuration.sensitivity.configuration)
        self.server = server
        self.onAlert = onAlert
        self.onMotionLevel = onMotionLevel
    }

    func update(_ newConfiguration: Configuration) {
        lock.withLock {
            if newConfiguration.sensitivity != configuration.sensitivity {
                detector = MotionDetector(configuration: newConfiguration.sensitivity.configuration)
            }
            configuration = newConfiguration
        }
    }

    /// Called for every frame on the camera queue.
    func process(_ frame: CameraFrame) {
        let now = frame.capturedAt
        publishIfDue(frame, now: now)

        let due = lock.withLock { () -> Bool in
            guard now.timeIntervalSince(lastAnalysis) >= Self.analysisInterval else { return false }
            lastAnalysis = now
            return true
        }
        guard due, let luma = LumaFrame(bgra: frame.pixelBuffer) else { return }

        let decision = lock.withLock { () -> (result: MotionDetector.Result, alert: Bool, confirm: Bool) in
            let result = detector.process(luma)
            guard result.isMotion, now.timeIntervalSince(lastAlert) >= configuration.cooldown, !isConfirming else {
                return (result, false, false)
            }
            if configuration.requirePerson && !frame.isDemo {
                guard now.timeIntervalSince(lastConfirmAttempt) >= Self.confirmInterval else { return (result, false, false) }
                lastConfirmAttempt = now
                isConfirming = true
                return (result, false, true)
            }
            lastAlert = now
            return (result, true, false)
        }
        onMotionLevel(decision.result.changedFraction)

        if decision.alert {
            raise(frame, person: false, fraction: decision.result.changedFraction)
        } else if decision.confirm {
            let fraction = decision.result.changedFraction
            Task.detached(priority: .utility) { [self] in
                let people = await HumanDetector.people(in: frame.pixelBuffer)
                let confirmed = lock.withLock { () -> Bool in
                    isConfirming = false
                    guard !people.isEmpty else { return false }
                    lastAlert = Date()
                    return true
                }
                if confirmed { raise(frame, person: true, fraction: fraction) }
            }
        }
    }

    private func publishIfDue(_ frame: CameraFrame, now: Date) {
        let interval = server.hasViewers ? 1 / max(1, lock.withLock { configuration.streamFPS }) : Self.idlePublishInterval
        let due = lock.withLock { () -> Bool in
            guard now.timeIntervalSince(lastPublish) >= interval else { return false }
            lastPublish = now
            return true
        }
        guard due, let jpeg = FrameEncoder.jpeg(from: frame.pixelBuffer, maxDimension: Self.streamMaxDimension, quality: 0.6) else { return }
        server.publish(jpeg: jpeg)
    }

    private func raise(_ frame: CameraFrame, person: Bool, fraction: Double) {
        guard let jpeg = FrameEncoder.jpeg(from: frame.pixelBuffer, maxDimension: Self.snapshotMaxDimension, quality: 0.8) else { return }
        onAlert(Alert(jpeg: jpeg, personDetected: person, changedFraction: fraction))
    }
}
