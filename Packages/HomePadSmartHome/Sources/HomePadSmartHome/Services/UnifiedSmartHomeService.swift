import Foundation
import HomePadCore
import Observation

/// HomePad's `SmartHomeService`. Merges Apple Home, Home Assistant and the demo
/// backend behind one list of accessories, scenes and cameras with stable,
/// backend-prefixed IDs (`hk:`, `ha:`, `demo:`). The demo backend is active whenever
/// no real backend is set up, so the simulator always has data.
@MainActor
@Observable
final class UnifiedSmartHomeService: SmartHomeService {
    /// Accessories the person chose to show (see `HomeLayout`).
    private(set) var accessories: [HomeAccessory] = []
    private(set) var scenes: [HomeScene] = []
    private(set) var cameras: [HomeCamera] = []
    /// Everything, including hidden items, for the settings editors.
    private(set) var allAccessories: [HomeAccessory] = []
    private(set) var allCameras: [HomeCamera] = []
    private(set) var connectedBackends: Set<SmartHomeBackend> = []
    /// Home Assistant's GPS device trackers, for Find My. Only Home Assistant has
    /// them, and demo data has none: the Personal module brings its own.
    private(set) var trackedDevices: [TrackedDevice] = []
    private(set) var zones: [HomeZone] = []
    /// True while no real backend is configured and demo data fills the UI.
    private(set) var isShowingDemo = true
    /// An accessory whose controls the Home app should show (see `showControls(for:)`).
    /// The Home app clears it once it does.
    var requestedDetailID: HomeAccessory.ID?
    /// True when "cameras" was opened, so the Home app shows every camera. It
    /// clears it once it does.
    var requestsAllCameras = false
    /// A camera to show full screen or close, asked for by Home Assistant
    /// (`kiosk_show_camera`, `kiosk_hide_camera`). The Home app clears it once it does.
    var cameraRequest: CameraRequest?
    /// What the Home app shows full screen, for the assistant (`HomeScreenContext`).
    @ObservationIgnored var screenFocus = HomeScreenFocus()
    /// This HomePad as a device in Home Assistant, made by the module.
    @ObservationIgnored var homeAssistantDevice: HomeAssistantDevice?

    enum CameraRequest: Equatable {
        case show(HomeCamera.ID)
        case close
    }

    let homeAssistant: HomeAssistantBackend
    let homeKit: HomeKitBackend
    let demo: DemoBackend
    /// Plays Home Assistant cameras over WebRTC. Nil in tests, where feeds fall back.
    @ObservationIgnored let webRTC: WebRTCEngine?

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let household: Household
    @ObservationIgnored let events: EventBus
    /// Turns HomeKit IDs saved on another HomePad into this HomePad's (`localID(for:)`).
    @ObservationIgnored let homeKitIDs: HomeKitIDTranslator
    @ObservationIgnored let log = Log.make("SmartHome")

    init(settings: SettingsStore, household: Household, events: EventBus,
         homeAssistant: HomeAssistantBackend, homeKit: HomeKitBackend, demo: DemoBackend? = nil,
         webRTC: WebRTCEngine? = nil) {
        self.settings = settings
        self.household = household
        self.events = events
        self.homeAssistant = homeAssistant
        self.homeKit = homeKit
        self.demo = demo ?? DemoBackend()
        self.webRTC = webRTC
        self.homeKitIDs = HomeKitIDTranslator(settings: settings)
        for driver in drivers {
            driver.onChange = { [weak self] in self?.rebuild() }
            driver.onDoorbell = { [weak self] cameraID in self?.doorbellRang(cameraID: cameraID) }
        }
        homeKitIDs.onChange = { [weak self] in self?.rebuild() }
        let translator = homeKitIDs
        let trigger: () -> String? = {
            settings[SmartHomeSettings.doorbell].triggerID.map { translator.localID(for: $0) }
        }
        homeAssistant.doorbellTriggerID = {
            trigger().flatMap { BackendID.backend(of: $0) == .homeAssistant ? BackendID.localID(of: $0) : nil }
        }
        homeKit.doorbellTriggerID = trigger
        rebuild()
    }

    /// The app's service, with the real keychain-backed Home Assistant configuration.
    convenience init(services: AppServices) {
        self.init(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: HomeAssistantBackend(store: .live(settings: services.settings, keychain: services.keychain)),
            homeKit: HomeKitBackend(settings: services.settings),
            webRTC: WebRTCEngine(audioSession: services.audioSession, microphone: services.microphone)
        )
    }

    var drivers: [any SmartHomeBackendDriver] { [homeKit, homeAssistant, demo] }

    /// Real backends that are set up, or the demo when there are none.
    var activeDrivers: [any SmartHomeBackendDriver] {
        let real = drivers.filter(\.isConfigured)
        return real.isEmpty ? [demo] : real
    }

    func driver(for backend: SmartHomeBackend) -> any SmartHomeBackendDriver {
        switch backend {
        case .homeKit: homeKit
        case .homeAssistant: homeAssistant
        case .demo: demo
        }
    }

    func start() {
        homeKit.start()
        homeAssistant.start()
    }

    /// The accessories inside a group, including hidden ones.
    func members(of group: HomeAccessory) -> [HomeAccessory] {
        allAccessories.filter { $0.groupID == group.id }
    }

    /// Re-merges the backends. Called whenever one of them changes.
    func rebuild() {
        // The last directory Apple Home loaded. It stays after a disconnect, so
        // what this HomePad saved still reads the same on the others.
        if let directory = homeKit.directory { homeKitIDs.updateLocal(directory) }
        let active = activeDrivers
        let layout = self.layout
        let merged = active.flatMap(\.accessories)
        let mergedCameras = active.flatMap(\.cameras)
        if merged != allAccessories { allAccessories = merged }
        if mergedCameras != allCameras { allCameras = mergedCameras }
        let visible = merged.filter { layout.isVisible(id: $0.id, room: $0.room) }
        if visible != accessories { accessories = visible }
        let visibleCameras = mergedCameras.filter { layout.isVisible(id: $0.id, room: $0.room) }
        if visibleCameras != cameras { cameras = visibleCameras }
        let mergedScenes = active.flatMap(\.scenes)
        if mergedScenes != scenes { scenes = mergedScenes }
        let trackers = homeAssistant.isConfigured ? homeAssistant.trackedDevices : []
        if trackers != trackedDevices { trackedDevices = trackers }
        let mergedZones = homeAssistant.isConfigured ? homeAssistant.zones : []
        if mergedZones != zones { zones = mergedZones }
        let connected = Set(active.filter(\.status.isConnected).map(\.backend))
        if connected != connectedBackends { connectedBackends = connected }
        let demoOnly = active.count == 1 && active.first?.backend == .demo
        if demoOnly != isShowingDemo { isShowingDemo = demoOnly }
    }

    /// The name shown at the top of the Home app.
    var homeName: String {
        if !isShowingDemo {
            if let name = homeKit.selectedHomeName, homeKit.isConfigured { return name }
            if let name = homeAssistant.serverConfig?.locationName, homeAssistant.isConfigured { return name }
        }
        return "My Home"
    }

    // MARK: Showing controls

    /// Opens the Home app on one accessory's full controls, from a widget or Control Center.
    func showControls(for accessoryID: HomeAccessory.ID) {
        requestedDetailID = accessoryID
        events.post(.openApp(id: SmartHomeModule.homeAppID))
    }

    /// Opens the Home app on one camera, full screen.
    func showCamera(_ cameraID: HomeCamera.ID) {
        cameraRequest = .show(cameraID)
        events.post(.openApp(id: SmartHomeModule.homeAppID))
    }
}
