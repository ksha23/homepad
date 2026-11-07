import Foundation
import HAKit
import HomePadCore
import Observation

/// Home Assistant through HAKit. HAKit owns the WebSocket (auth, subscriptions,
/// pings and reconnecting with backoff) and REST calls. This class keeps the
/// entity states and registries, maps them to HomePad models, and runs commands.
@MainActor
@Observable
final class HomeAssistantBackend: SmartHomeBackendDriver {
    let backend = SmartHomeBackend.homeAssistant
    var status: BackendStatus = .notConfigured
    private(set) var accessories: [HomeAccessory] = []
    private(set) var scenes: [HomeScene] = []
    private(set) var cameras: [HomeCamera] = []
    /// GPS device trackers, for Find My (see `HATrackerMapper`).
    private(set) var trackedDevices: [TrackedDevice] = []
    private(set) var zones: [HomeZone] = []
    private(set) var configuration: HomeAssistantConfiguration?
    var serverConfig: HAServerConfig?
    /// Counts connections that reached ready. Camera views restart their feeds when it changes.
    var connectionEpoch = 0

    var isConfigured: Bool { configuration != nil }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onDoorbell: ((HomeCamera.ID?) -> Void)?
    /// Local entity ID of an extra doorbell trigger picked in Settings.
    @ObservationIgnored var doorbellTriggerID: () -> String? = { nil }

    @ObservationIgnored var states: [String: HAState] = [:]
    @ObservationIgnored var registry = HARegistry()
    @ObservationIgnored var connection: HAConnection?
    @ObservationIgnored var subscriptions: [HACancellable] = []
    @ObservationIgnored var connectionObserver: ConnectionObserver?
    @ObservationIgnored let store: HomeAssistantConfigurationStore
    @ObservationIgnored let makeConnection: (HAConnectionConfiguration) -> HAConnection
    @ObservationIgnored let session: URLSession
    @ObservationIgnored let log = Log.make("HomeAssistant")
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    /// State changes are coalesced so a busy instance does not redraw the UI on every event.
    @ObservationIgnored var rebuildDelay: Duration = .milliseconds(250)
    /// The pending registry reload (see `scheduleRegistryReload`).
    @ObservationIgnored var registryReloadTask: Task<Void, Never>?
    /// Registry events come in bursts (an integration reloading renames or moves
    /// many entities at once), so one reload waits this long after the last of them.
    @ObservationIgnored var registryReloadDelay: Duration = .seconds(1)
    /// This HomePad's `mobile_app` webhook while it is a device in Home Assistant.
    /// Setting it opens the push channel on the connection (`HomeAssistantBackend+PushChannel`).
    @ObservationIgnored var pushChannelWebhookID: String? {
        didSet { if pushChannelWebhookID != oldValue { reopenPushChannel() } }
    }
    @ObservationIgnored var pushChannel: HACancellable?
    /// A notification Home Assistant sent this HomePad: `{"message", "title", "data"}`.
    @ObservationIgnored var onPushNotification: ((JSONValue) -> Void)?
    /// Home Assistant refused the push channel: whether it no longer knows the
    /// webhook, and its reason.
    @ObservationIgnored var onPushChannelRefused: ((_ webhookUnknown: Bool, _ reason: String) -> Void)?

    init(
        store: HomeAssistantConfigurationStore,
        session: URLSession = .shared,
        makeConnection: @escaping (HAConnectionConfiguration) -> HAConnection = {
            HAKit.connection(configuration: $0, connectAutomatically: false)
        }
    ) {
        self.store = store
        self.session = session
        self.makeConnection = makeConnection
        self.configuration = store.load()
    }

    // MARK: Configuration

    /// Saves a new URL and token (or nil to forget them) and reconnects.
    func configure(_ configuration: HomeAssistantConfiguration?) {
        store.save(configuration)
        self.configuration = configuration
        disconnect()
        states = [:]
        registry = HARegistry()
        rebuildNow()
        start()
    }

    // MARK: Mapping

    var mappingContext: HAStateMapper.Context {
        HAStateMapper.Context(
            registry: registry,
            temperatureUnit: serverConfig?.temperatureUnit ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius),
            baseURL: configuration?.baseURL,
            doorbellTriggerID: doorbellTriggerID()
        )
    }

    func scheduleRebuild() {
        guard rebuildTask == nil else { return }
        rebuildTask = Task { [weak self, rebuildDelay] in
            try? await Task.sleep(for: rebuildDelay)
            self?.rebuildNow()
        }
    }

    /// Re-maps every state right away and tells the unified service.
    func rebuildNow() {
        rebuildTask?.cancel()
        rebuildTask = nil
        let output = HAStateMapper.map(Array(states.values), context: mappingContext)
        if output.accessories != accessories { accessories = output.accessories }
        if output.scenes != scenes { scenes = output.scenes }
        if output.cameras != cameras { cameras = output.cameras }
        let trackers = HATrackerMapper.map(Array(states.values), registry: registry)
        if trackers.devices != trackedDevices { trackedDevices = trackers.devices }
        if trackers.zones != zones { zones = trackers.zones }
        onChange?()
    }

    /// Applies one `state_changed` event and rings the doorbell when it is a press.
    func apply(_ change: HAStateChange) {
        states[change.entityID] = change.newState
        if HADoorbellDetector.isRing(change, configuredTriggerID: doorbellTriggerID()) {
            let cameraID = HADoorbellDetector.cameraEntityID(
                forDoorbell: change.entityID,
                cameraEntityIDs: states.keys.filter { $0.hasPrefix("camera.") },
                registry: registry
            )
            log.info("Doorbell pressed")
            onDoorbell?(cameraID.map { BackendID.make(.homeAssistant, $0) })
        }
        scheduleRebuild()
    }

    // MARK: SmartHomeBackendDriver

    func refresh() async {
        guard let connection else { return }
        do {
            let loaded = try HAResponses.states(try await connection.send(HARequests.states))
            // A new address or token replaced the connection while this was loading.
            guard connection === self.connection else { return }
            states = Dictionary(loaded.map { ($0.entityID, $0) }, uniquingKeysWith: { $1 })
            rebuildNow()
        } catch {
            log.error("Refreshing states failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func perform(_ command: AccessoryCommand, on accessory: HomeAccessory) async throws {
        let entityID = BackendID.localID(of: accessory.id)
        try await execute(HACommandMapper.serviceCall(for: command, entityID: entityID, state: states[entityID]))
    }

    func activateScene(_ scene: HomeScene) async throws {
        try await execute(HACommandMapper.sceneCall(entityID: BackendID.localID(of: scene.id)))
    }

    func callService(domain: String, service: String, data: JSONValue) async throws {
        try await execute(HAServiceCall(domain: domain, service: service, data: data.objectValue ?? [:]))
    }

    /// A raw WebSocket command, answered with its `result` as JSON.
    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        guard let connection, status.isConnected else { throw SmartHomeError.notConnected(.homeAssistant) }
        log.info("Sending \(type, privacy: .public)")
        let fields = data.objectValue?.mapValues(\.foundationValue) ?? [:]
        do {
            return JSONValue(haData: try await connection.send(HARequests.command(type, data: fields)))
        } catch {
            throw SmartHomeError.backend(error.localizedDescription)
        }
    }

    /// Kind of the accessory for a local entity ID, for the security policy.
    func kind(ofEntity entityID: String) -> AccessoryKind? {
        accessories.first { $0.id == BackendID.make(.homeAssistant, entityID) }?.kind
    }

    func execute(_ call: HAServiceCall) async throws {
        guard let connection, status.isConnected else { throw SmartHomeError.notConnected(.homeAssistant) }
        log.info("Calling \(call.domain, privacy: .public).\(call.service, privacy: .public)")
        do {
            _ = try await connection.send(call.request)
        } catch {
            throw SmartHomeError.backend(error.localizedDescription)
        }
    }
}
