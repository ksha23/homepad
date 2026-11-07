import Foundation
import HomePadCore
import Observation

/// This HomePad as a device in Home Assistant, the way the Home Assistant app
/// and Kiosk Satellite are: it registers with the `mobile_app` integration,
/// reports its sensors (`MobileAppSensor`) as they change, and takes commands
/// from `notify.mobile_app_<device>` over the push channel on the WebSocket the
/// backend already has (`MobileAppCommand`).
///
/// Off until someone turns it on in Settings > Smart Home. Each iPad registers
/// with its own device ID, named after its room, and registering again replaces
/// the device instead of adding one. Faces, face data, photos and sound never
/// go to Home Assistant.
@MainActor
@Observable
final class HomeAssistantDevice {
    enum Status: Equatable {
        case off
        case needsHomeAssistant
        case waitingForConnection
        case registering
        case active
        case failed(String)

        /// One short line for Settings.
        var summary: String {
            switch self {
            case .off: "Off"
            case .needsHomeAssistant: "Connect Home Assistant first"
            case .waitingForConnection: "Waiting for Home Assistant"
            case .registering: "Registering"
            case .active: "Registered"
            case .failed(let message): message
            }
        }
    }

    var status: Status = .off
    /// What Home Assistant knows this HomePad as, while registered.
    var registration: MobileAppRegistration.Stored?
    /// Why commands cannot arrive, when Home Assistant refused the push channel.
    var commandsProblem: String?
    /// A notification from Home Assistant without a command, shown as a banner.
    var notification: HomeAssistantNotification?
    /// What happened at the last Remove from Home Assistant.
    var removalMessage: String?
    var isRemoving = false

    @ObservationIgnored let services: AppServices
    @ObservationIgnored weak var registry: ModuleRegistry?
    @ObservationIgnored let smartHome: UnifiedSmartHomeService
    @ObservationIgnored let transport: any MobileAppTransport
    @ObservationIgnored let store: MobileAppRegistrationStore
    @ObservationIgnored let info: MobileAppDeviceInfo
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Inputs tests give in place of the services'.
    @ObservationIgnored var inputsOverride: (() -> MobileAppSensorInputs)?
    @ObservationIgnored var throttle = MobileAppReportThrottle()
    /// How long a banner stays.
    @ObservationIgnored var notificationDuration: Duration = .seconds(10)
    /// After a failure nothing is sent until then, growing from 30 s to 10 minutes.
    @ObservationIgnored var backoffUntil: Date?
    @ObservationIgnored var backoff: TimeInterval = 30
    @ObservationIgnored var isReporting = false
    /// The address and token reporting started with. A new one starts over.
    @ObservationIgnored var reportingConfiguration: HomeAssistantConfiguration?
    @ObservationIgnored var setupTask: Task<Void, Never>?
    @ObservationIgnored var sendTask: Task<Void, Never>?
    @ObservationIgnored var scheduledSend: Task<Void, Never>?
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored var notificationTask: Task<Void, Never>?
    /// Bumped whenever reporting stops, so work started before it is dropped.
    @ObservationIgnored var generation = 0
    @ObservationIgnored let log = Log.make("HomeAssistantDevice")

    init(services: AppServices, registry: ModuleRegistry?, smartHome: UnifiedSmartHomeService,
         transport: (any MobileAppTransport)? = nil,
         store: MobileAppRegistrationStore? = nil, info: MobileAppDeviceInfo? = nil) {
        self.services = services
        self.registry = registry
        self.smartHome = smartHome
        self.transport = transport ?? URLSessionMobileAppTransport()
        self.store = store ?? .live(settings: services.settings, service: services.keychain.service)
        self.info = info ?? .current
    }

    var backend: HomeAssistantBackend { smartHome.homeAssistant }

    /// The sensors' inputs right now.
    func readInputs() -> MobileAppSensorInputs {
        inputsOverride?() ?? MobileAppSensorInputs.current(services: services, registry: registry)
    }

    /// The Settings switch. Off by default.
    var isEnabled: Bool {
        get { services.settings[SmartHomeSettings.homeAssistantDeviceEnabled] }
        set { services.settings[SmartHomeSettings.homeAssistantDeviceEnabled] = newValue }
    }

    /// "Kitchen HomePad", after the room in Devices & Sharing.
    var deviceName: String {
        MobileAppNaming.deviceName(room: services.settings[CoreSettings.roomName])
    }

    /// The notify action that reaches this HomePad, while registered.
    var notifyAction: String? {
        registration.map { "notify." + MobileAppNaming.notifyService(deviceName: $0.deviceName) }
    }

    // MARK: Lifecycle

    /// Starts following the switch, the connection and the sensors' inputs.
    func start() {
        backend.onPushNotification = { [weak self] in self?.receive($0) }
        backend.onPushChannelRefused = { [weak self] unknown, reason in
            self?.pushChannelRefused(webhookUnknown: unknown, reason: reason)
        }
        registration = store.load()
        observe()
        reconcile()
    }

    /// What decides whether to register, report or stop.
    private struct Lifecycle: Equatable {
        var isEnabled: Bool
        var configuration: HomeAssistantConfiguration?
        var isConnected: Bool
        var deviceName: String
    }

    private var lifecycle: Lifecycle {
        Lifecycle(isEnabled: isEnabled, configuration: backend.configuration,
                  isConnected: backend.status.isConnected, deviceName: deviceName)
    }

    /// Re-arms after each change. The sensors' inputs change at most a few
    /// times a second (presence publishes only meaningful changes), and the
    /// throttle decides what goes out.
    private func observe() {
        withObservationTracking {
            _ = lifecycle
            _ = readInputs()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observe()
                self.reconcile()
                self.inputsChanged()
            }
        }
    }

    /// Brings the device in line with the switch and the connection.
    func reconcile() {
        let now = lifecycle
        guard now.isEnabled else { return turnOff() }
        guard let configuration = now.configuration else {
            if isReporting || setupTask != nil { stopReporting() }
            if status != .needsHomeAssistant { status = .needsHomeAssistant }
            return
        }
        if isReporting, reportingConfiguration != configuration {
            // Another address or token: start over, which registers again if needed.
            stopReporting()
        }
        guard now.isConnected else {
            if status != .waitingForConnection { status = .waitingForConnection }
            return
        }
        guard setupTask == nil, retryTask == nil else { return }
        if isReporting {
            if status != .active { status = .active }
            if let registration, registration.deviceName != now.deviceName { rename(registration, on: configuration) }
            return
        }
        setUp(on: configuration)
    }

    /// The switch went off: Home Assistant shows the sensors as unavailable.
    private func turnOff() {
        let wasReporting = isReporting
        let configuration = reportingConfiguration
        stopReporting()
        if status != .off { status = .off }
        guard wasReporting, let configuration, let registration else { return }
        let unavailable = MobileAppSensor.allCases.map { sensor in
            var state = readInputs().state(of: sensor)
            state.state = MobileAppSensorState.unavailable
            return state
        }
        Task { [transport, log] in
            do {
                _ = try await transport.send(MobileAppSensorState.updateMessage(unavailable),
                                             webhookID: registration.webhookID, on: configuration)
            } catch {
                log.error("Marking the sensors unavailable failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Stops everything in flight and closes the push channel. Keeps the registration.
    func stopReporting() {
        generation += 1
        for task in [setupTask, sendTask, scheduledSend, retryTask] { task?.cancel() }
        setupTask = nil
        sendTask = nil
        scheduledSend = nil
        retryTask = nil
        isReporting = false
        reportingConfiguration = nil
        backend.pushChannelWebhookID = nil
    }

    // MARK: Registering

    /// Registers when needed, registers every sensor with its value, then reports changes.
    private func setUp(on configuration: HomeAssistantConfiguration) {
        status = .registering
        removalMessage = nil
        let generation = self.generation
        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                var stored = try await self.registration(on: configuration)
                if try await !self.registerSensors(stored, on: configuration) {
                    // Home Assistant forgot the device: the same device ID takes its place again.
                    stored = try await self.register(on: configuration)
                    guard try await self.registerSensors(stored, on: configuration) else {
                        throw SmartHomeError.backend("Home Assistant did not take the new registration.")
                    }
                }
                guard generation == self.generation else { return }
                self.setupTask = nil
                self.beginReporting(stored, on: configuration)
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                self.setupTask = nil
                self.failed(error)
            }
        }
    }

    /// The saved registration when it belongs to this Home Assistant, renamed when
    /// the room or the version changed, or a new one.
    private func registration(on configuration: HomeAssistantConfiguration) async throws -> MobileAppRegistration.Stored {
        let name = deviceName
        guard var stored = store.load(), stored.instanceURL == configuration.baseURL.absoluteString else {
            return try await register(on: configuration)
        }
        guard stored.deviceName != name || stored.appVersion != info.appVersion else { return stored }
        switch try await transport.send(MobileAppRegistration.updateMessage(deviceName: name, info: info),
                                        webhookID: stored.webhookID, on: configuration) {
        case .handled:
            stored.deviceName = name
            stored.appVersion = info.appVersion
            save(stored)
            return stored
        case .gone, .unknownWebhook:
            return try await register(on: configuration)
        }
    }

    /// `POST /api/mobile_app/registrations` with this iPad's device ID.
    func register(on configuration: HomeAssistantConfiguration) async throws -> MobileAppRegistration.Stored {
        let name = deviceName
        let body = MobileAppRegistration.body(deviceID: store.deviceID(), deviceName: name, info: info)
        let response = try await transport.register(body, on: configuration)
        let stored = MobileAppRegistration.Stored(
            webhookID: try MobileAppRegistration.webhookID(from: response),
            instanceURL: configuration.baseURL.absoluteString,
            deviceName: name, appVersion: info.appVersion, registeredAt: clock()
        )
        save(stored)
        throttle.reset()
        log.info("Registered with Home Assistant as \(name, privacy: .public)")
        return stored
    }

    /// Registers every sensor with its current value. False when Home Assistant
    /// no longer knows the webhook.
    private func registerSensors(_ stored: MobileAppRegistration.Stored, on configuration: HomeAssistantConfiguration) async throws -> Bool {
        throttle.noteSending(at: clock())
        for state in readInputs().states {
            switch try await transport.send(state.registerMessage, webhookID: stored.webhookID, on: configuration) {
            case .handled(let reply):
                if reply["success"]?.boolValue == true {
                    throttle.noteReported([state])
                } else {
                    log.error("Home Assistant did not take the \(state.sensor.uniqueID, privacy: .public) sensor")
                }
            case .gone, .unknownWebhook:
                return false
            }
        }
        return true
    }

    private func beginReporting(_ stored: MobileAppRegistration.Stored, on configuration: HomeAssistantConfiguration) {
        registration = stored
        reportingConfiguration = configuration
        isReporting = true
        commandsProblem = nil
        backoff = 30
        backoffUntil = nil
        status = .active
        backend.pushChannelWebhookID = stored.webhookID
        // Anything that changed while the sensors were registering.
        inputsChanged()
    }

    /// The room changed while reporting: Home Assistant renames the device and its notify action.
    private func rename(_ stored: MobileAppRegistration.Stored, on configuration: HomeAssistantConfiguration) {
        let generation = self.generation
        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let renamed = try await self.registration(on: configuration)
                guard generation == self.generation else { return }
                self.setupTask = nil
                self.registration = renamed
                if renamed.webhookID != stored.webhookID {
                    // It registered again, so the sensors go again and the channel moves to the new webhook.
                    self.stopReporting()
                    self.reconcile()
                }
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                self.setupTask = nil
                self.failed(error)
            }
        }
    }

    func save(_ stored: MobileAppRegistration.Stored?) {
        store.save(stored)
        registration = stored
    }

    /// Home Assistant deleted the registration or forgot the webhook: register again.
    func registrationLost() {
        log.info("Home Assistant no longer knows this HomePad, registering again")
        save(nil)
        throttle.reset()
        stopReporting()
        reconcile()
    }

    /// Shows why and tries again later, waiting longer each time up to 10 minutes.
    func failed(_ error: Error) {
        log.error("Home Assistant device: \(error.localizedDescription, privacy: .public)")
        status = .failed(error.localizedDescription)
        let delay = backoff
        backoff = min(backoff * 2, 600)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.reconcile()
        }
    }

    private func pushChannelRefused(webhookUnknown: Bool, reason: String) {
        guard isReporting else { return }
        if webhookUnknown {
            registrationLost()
        } else {
            commandsProblem = reason
        }
    }
}
