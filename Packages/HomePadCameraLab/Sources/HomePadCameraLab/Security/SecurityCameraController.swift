import Foundation
import HomePadCore
import Observation

/// Security Camera mode: something HomeView cannot do. Watches a camera for
/// motion, confirms people with Vision, keeps recent snapshots, serves an
/// MJPEG stream to Home Assistant, and optionally calls a webhook.
///
/// While it watches, the presence sensor is paused because iOS allows one
/// capture session. Schedules keep that window as short as possible.
@MainActor
@Observable
final class SecurityCameraController {
    static let owner = "cameralab.security"
    static let eventSource = "cameralab.security"

    private(set) var isEnabled = false
    private(set) var isWatching = false
    private(set) var problem: String?
    private(set) var serverState: MJPEGServer.State = .stopped
    private(set) var viewerCount = 0
    /// Changed fraction of the latest analyzed frame, for the live meter.
    private(set) var motionLevel = 0.0
    private(set) var lastAlertAt: Date?
    private(set) var snapshots: [MotionSnapshot] = []
    private(set) var token = ""

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let broker: CameraBroker
    @ObservationIgnored private let server = MJPEGServer()
    @ObservationIgnored private let ringBuffer: SnapshotRingBuffer
    @ObservationIgnored private var pipeline: SecurityFramePipeline?
    @ObservationIgnored private var consumer: (hub: FrameHub, id: UUID)?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var lastSeenSomeone: Date?
    @ObservationIgnored private let log = Log.make("CameraLab.Security")

    init(services: AppServices, broker: CameraBroker) {
        self.services = services
        self.broker = broker
        ringBuffer = SnapshotRingBuffer(limit: services.settings[CameraLabSettings.securitySnapshotLimit])
        snapshots = ringBuffer.snapshots
        token = Self.loadOrCreateToken(services.keychain)
        server.onStateChange = { [weak self] state in self?.serverState = state }
        server.onStreamCountChange = { [weak self] count in self?.viewerCount = count }
    }

    // MARK: Settings-backed values

    var settings: SettingsStore { services.settings }
    var schedule: SecuritySchedule { settings[CameraLabSettings.securitySchedule] }
    var camera: CameraPosition { settings[CameraLabSettings.securityCamera] }
    var port: Int { settings[CameraLabSettings.securityPort] }

    var webhookURL: String {
        get { services.keychain.string(for: CameraLabSecrets.webhookURL) ?? "" }
        set { services.keychain.set(newValue.isEmpty ? nil : newValue, for: CameraLabSecrets.webhookURL) }
    }

    /// The values to type into Home Assistant's "MJPEG IP Camera" integration.
    var homeAssistantSetup: HomeAssistantCameraSetup {
        HomeAssistantCameraSetup(host: LocalNetworkAddress.current(), port: port, token: token)
    }

    func url(for snapshot: MotionSnapshot) -> URL { ringBuffer.url(for: snapshot) }

    // MARK: On and off

    /// Restores the mode after a relaunch, so an always-on iPad keeps guarding.
    func restoreIfNeeded() {
        if settings[CameraLabSettings.securityEnabled] { setEnabled(true) }
    }

    func setEnabled(_ enabled: Bool) {
        settings[CameraLabSettings.securityEnabled] = enabled
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            lastSeenSomeone = Date()
            server.start(port: UInt16(clamping: port), token: token)
            startScheduleLoop()
        } else {
            scheduleTask?.cancel()
            scheduleTask = nil
            stopWatching()
            server.stop()
            problem = nil
        }
    }

    /// Re-applies settings that changed in the Settings pane.
    func settingsChanged() {
        let limit = settings[CameraLabSettings.securitySnapshotLimit]
        if limit != ringBuffer.limit {
            ringBuffer.limit = limit
            snapshots = ringBuffer.snapshots
        }
        pipeline?.update(pipelineConfiguration)
        guard isEnabled else { return }
        if case .listening(let listening) = serverState, Int(listening) != port {
            server.start(port: UInt16(clamping: port), token: token)
        }
        if isWatching, broker.holds.first(where: { $0.owner == Self.owner })?.camera != camera {
            stopWatching()
        }
        evaluateSchedule()
    }

    func regenerateToken() {
        token = AccessToken.generate()
        services.keychain.set(token, for: CameraLabSecrets.streamToken)
        server.updateToken(token)
    }

    func clearSnapshots() {
        ringBuffer.removeAll()
        snapshots = []
    }

    // MARK: Schedule

    private func startScheduleLoop() {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluateSchedule()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func evaluateSchedule() {
        guard isEnabled else { return }
        if services.displayCondition == .active || (!isWatching && services.presence.snapshot.isSomeonePresent) {
            lastSeenSomeone = Date()
        }
        let shouldWatch = schedule.shouldWatch(now: Date(), lastSeenSomeone: lastSeenSomeone)
        if shouldWatch, !isWatching {
            startWatching()
        } else if !shouldWatch, isWatching {
            stopWatching()
        }
    }

    private var pipelineConfiguration: SecurityFramePipeline.Configuration {
        SecurityFramePipeline.Configuration(
            sensitivity: settings[CameraLabSettings.securitySensitivity],
            requirePerson: settings[CameraLabSettings.securityRequirePerson]
        )
    }

    private func startWatching() {
        if case .denied(let reason) = broker.acquire(Self.owner, title: "Security Camera", camera: camera) {
            problem = reason
            return
        }
        guard let hub = broker.hub else { return }
        let pipeline = SecurityFramePipeline(
            configuration: pipelineConfiguration, server: server,
            onAlert: { [weak self] alert in Task { @MainActor in self?.handle(alert) } },
            onMotionLevel: { [weak self] level in Task { @MainActor in self?.motionLevel = level } }
        )
        self.pipeline = pipeline
        consumer = (hub, hub.addConsumer { frame in pipeline.process(frame) })
        isWatching = true
        problem = nil
        log.info("Security Camera watching with the \(self.camera.rawValue, privacy: .public) camera")
    }

    private func stopWatching() {
        if let consumer { consumer.hub.removeConsumer(consumer.id) }
        consumer = nil
        pipeline = nil
        broker.release(Self.owner)
        isWatching = false
        motionLevel = 0
    }

    // MARK: Alerts

    private func handle(_ alert: SecurityFramePipeline.Alert) {
        guard isWatching else { return }
        lastAlertAt = Date()
        do {
            try ringBuffer.add(jpeg: alert.jpeg, personDetected: alert.personDetected)
            snapshots = ringBuffer.snapshots
        } catch {
            log.error("Could not save a motion snapshot: \(error.localizedDescription, privacy: .public)")
        }
        services.events.post(.motionDetected(source: Self.eventSource))
        if let url = MotionWebhook.validatedURL(webhookURL) {
            let payload = MotionAlertPayload(
                source: Self.eventSource, personDetected: alert.personDetected,
                changedFraction: alert.changedFraction, time: Date(),
                snapshotURL: homeAssistantSetup.snapshotURL
            )
            Task.detached { await MotionWebhook.post(payload, to: url) }
        }
    }

    private static func loadOrCreateToken(_ keychain: KeychainStore) -> String {
        if let saved = keychain.string(for: CameraLabSecrets.streamToken), saved.count >= AccessToken.minimumLength {
            return saved
        }
        let token = AccessToken.generate()
        keychain.set(token, for: CameraLabSecrets.streamToken)
        return token
    }
}
