import Foundation
import HomePadCore
import Observation

/// Shares one camera feed between Camera Lab tools and keeps Core's capture
/// arbiter (`services.capture`) in sync, so the presence sensor yields while
/// any tool holds a camera.
///
/// iOS runs one capture session at a time. Tools that read frames (Ask About This,
/// Security Camera, Timelapse) share the same feed when they want the same camera.
/// Tools whose system UI owns the camera (document camera, Live Text scanner,
/// RoomPlan) need it exclusively.
///
///     guard case .granted = broker.acquire("cameralab.ask", title: "Ask About This", camera: .back) else { ... }
///     defer { broker.release("cameralab.ask") }
@MainActor
@Observable
final class CameraBroker {
    struct Hold: Equatable {
        let owner: String
        let title: String
        let camera: CameraPosition
        /// The tool shows Apple's own camera UI, which runs its own capture session.
        let usesSystemCapture: Bool
    }

    enum Access: Equatable {
        case granted
        case denied(String)
    }

    private(set) var holds: [Hold] = []
    private(set) var status: FeedStatus = .stopped
    private(set) var producer: (any FrameProducer)?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var claimedOwner: String?
    @ObservationIgnored private let log = Log.make("CameraLab.Broker")

    init(services: AppServices) {
        self.services = services
        watchCoordinator()
    }

    /// Frames of the running feed, if any.
    var hub: FrameHub? { producer?.hub }
    var isDemo: Bool { producer?.isDemo ?? false }
    var liveSession: LiveCameraSession? { producer as? LiveCameraSession }

    /// True when the camera exists here, or the simulator can stand in with a demo feed.
    static func canProvideFeed(_ camera: CameraPosition) -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        LiveCameraSession.device(for: camera) != nil
        #endif
    }

    func isHeld(by owner: String) -> Bool { holds.contains { $0.owner == owner } }

    // MARK: Claims

    /// Asks for a camera. Same-camera feed users share. Anything else conflicts.
    func acquire(_ owner: String, title: String, camera: CameraPosition, usesSystemCapture: Bool = false) -> Access {
        guard services.capture.camerasAllowed else {
            return .denied("Cameras are turned off. Turn them back on in Control Center.")
        }
        let others = holds.filter { $0.owner != owner }
        if let conflict = others.first(where: { usesSystemCapture || $0.usesSystemCapture || $0.camera != camera }) {
            return .denied("\(conflict.title) is using the \(conflict.camera.title.lowercased()). Stop it first.")
        }
        if !usesSystemCapture, !Self.canProvideFeed(camera) {
            return .denied("This iPad has no \(camera.title.lowercased()).")
        }
        holds.removeAll { $0.owner == owner }
        holds.append(Hold(owner: owner, title: title, camera: camera, usesSystemCapture: usesSystemCapture))
        syncCoordinator()
        if !usesSystemCapture { startFeed(camera) }
        log.info("Camera granted to \(owner, privacy: .public)")
        return .granted
    }

    func release(_ owner: String) {
        guard isHeld(by: owner) else { return }
        holds.removeAll { $0.owner == owner }
        syncCoordinator()
        if !holds.contains(where: { !$0.usesSystemCapture }) { stopFeed() }
        log.info("Camera released by \(owner, privacy: .public)")
    }

    // MARK: Feed

    private func startFeed(_ camera: CameraPosition) {
        guard let producer = producer(for: camera) else { return }
        if self.producer !== producer {
            self.producer?.stop()
            producer.onStatusChange = { [weak self] status in self?.status = status }
            self.producer = producer
        }
        guard producer.position != camera else { return }
        // The presence sensor needs a moment to close the camera before ours can open.
        Task { [weak self] in
            guard let self else { return }
            await self.services.capture.waitForBackgroundSensorRelease()
            let stillWanted = self.holds.contains { !$0.usesSystemCapture && $0.camera == camera }
            guard stillWanted, self.producer === producer, producer.position != camera else { return }
            producer.start(position: camera)
        }
    }

    private func stopFeed() {
        producer?.stop()
    }

    private func producer(for camera: CameraPosition) -> (any FrameProducer)? {
        if LiveCameraSession.device(for: camera) != nil {
            return (producer as? LiveCameraSession) ?? LiveCameraSession()
        }
        #if targetEnvironment(simulator)
        return (producer as? DemoFrameGenerator) ?? DemoFrameGenerator()
        #else
        return nil
        #endif
    }

    // MARK: Core arbiter

    /// Mirrors the newest hold into `services.capture`, or releases when nobody holds a camera.
    private func syncCoordinator() {
        if let top = holds.last {
            services.capture.claim(top.owner, camera: top.camera.coordinatorCamera)
            claimedOwner = top.owner
        } else if let claimed = claimedOwner {
            services.capture.release(claimed)
            claimedOwner = nil
        }
    }

    /// Reacts to the privacy switch and to other modules releasing a claim over ours.
    private func watchCoordinator() {
        withObservationTracking {
            _ = services.capture.foregroundClaim
            _ = services.capture.camerasAllowed
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.coordinatorChanged()
                self?.watchCoordinator()
            }
        }
    }

    private func coordinatorChanged() {
        guard !holds.isEmpty else { return }
        if !services.capture.camerasAllowed {
            stopFeed()
            status = .failed("Cameras are turned off. Turn them back on in Control Center.")
            return
        }
        if let feedHold = holds.last(where: { !$0.usesSystemCapture }), producer?.position == nil {
            startFeed(feedHold.camera)
        }
        if services.capture.foregroundClaim == nil {
            syncCoordinator()
        }
    }
}
