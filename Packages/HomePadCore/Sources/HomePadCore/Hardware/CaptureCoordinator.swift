import Foundation
import Observation

/// Arbitrates the cameras. iOS runs one capture session at a time, so the
/// always-on presence sensor (front camera or TrueDepth) yields whenever a
/// foreground feature claims a camera (Mirror, back-camera Lab, scanner).
///
///     services.capture.claim("cameralab.scanner", camera: .back)
///     defer { services.capture.release("cameralab.scanner") }
///
/// The Presence module watches `foregroundClaim` and stops its session while it is set.
@MainActor
@Observable
public final class CaptureCoordinator {
    public enum Camera: String, Sendable {
        case front, back, trueDepth
    }

    public struct Claim: Equatable, Sendable {
        public let owner: String
        public let camera: Camera
        public let since: Date
    }

    /// Every active claim, oldest first. A feature that opens another camera
    /// feature on top (a scanner inside the Lab) stacks its claim.
    public private(set) var claims: [Claim] = []

    /// The feature currently using a camera in the foreground (the newest claim), if any.
    public var foregroundClaim: Claim? { claims.last }

    /// Master privacy switch. When false nobody may use any camera.
    public var camerasAllowed = true

    /// True while the background presence sensor still has a camera open.
    /// It stays true for a moment after a claim, until the sensor's session has
    /// actually stopped. Starting another capture session before then gets no frames.
    public private(set) var isBackgroundSensorUsingCamera = false

    /// Called by the Presence module when its camera opens and once it has fully closed.
    public func setBackgroundSensorUsingCamera(_ inUse: Bool) {
        isBackgroundSensorUsingCamera = inUse
    }

    public init() {}

    /// Returns false when cameras are disabled by the privacy switch.
    @discardableResult
    public func claim(_ owner: String, camera: Camera) -> Bool {
        guard camerasAllowed else { return false }
        claims.removeAll { $0.owner == owner }
        claims.append(Claim(owner: owner, camera: camera, since: Date()))
        return true
    }

    public func release(_ owner: String) {
        claims.removeAll { $0.owner == owner }
    }

    /// Claims a camera and waits until the background sensor has let go of it,
    /// so a capture session started right after this returns receives frames.
    /// Returns false when cameras are off or the claim was taken away meanwhile.
    public func claimWhenReady(_ owner: String, camera: Camera, timeout: Duration = .seconds(3)) async -> Bool {
        guard claim(owner, camera: camera) else { return false }
        await waitForBackgroundSensorRelease(timeout: timeout)
        return claims.contains { $0.owner == owner }
    }

    /// Waits (up to `timeout`) until the background sensor has closed its camera.
    public func waitForBackgroundSensorRelease(timeout: Duration = .seconds(3)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while isBackgroundSensorUsingCamera, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// True when the background presence sensor may run.
    public var isPresenceSensingAllowed: Bool {
        camerasAllowed && foregroundClaim == nil
    }
}
