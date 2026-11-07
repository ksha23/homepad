import Foundation
@preconcurrency import HomeKit
import HomePadCore
import Observation

/// Apple Home through HomeKit. The permission prompt only appears after the person
/// chooses to connect it in Settings or from the Home app.
@MainActor
@Observable
final class HomeKitBackend: SmartHomeBackendDriver {
    let backend = SmartHomeBackend.homeKit
    private(set) var access: HomeKitAccess = .notRequested
    private(set) var homes: [HomeKitHomeSummary] = []
    private(set) var selectedHomeName: String?
    private(set) var accessories: [HomeAccessory] = []
    private(set) var scenes: [HomeScene] = []
    private(set) var cameras: [HomeCamera] = []
    /// What this HomePad calls each HomeKit object in every home, which the
    /// household's other HomePads use to read the IDs it saves. Nil until
    /// Apple Home has loaded, and while it is not connected.
    private(set) var directory: HomeKitDirectory?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onDoorbell: ((HomeCamera.ID?) -> Void)?
    /// Unified ID of an extra doorbell trigger picked in Settings.
    @ObservationIgnored var doorbellTriggerID: () -> String? = { nil }

    /// Live streams shared by every camera view.
    @ObservationIgnored let streams = HomeKitStreamHub()
    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private let proxy = HomeKitDelegateProxy()
    /// The HomeKit service behind each accessory ID.
    @ObservationIgnored private(set) var services: [String: HMService] = [:]
    @ObservationIgnored private(set) var cameraProfiles: [String: HMCameraProfile] = [:]
    /// The HomeKit action set behind each scene ID.
    @ObservationIgnored private(set) var actionSets: [String: HMActionSet] = [:]
    /// Apple Home groups by ID, with their names, for rebuilding when a member changes.
    @ObservationIgnored private var groupNames: [String: String] = [:]
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let log = Log.make("HomeKit")

    init(settings: SettingsStore) {
        self.settings = settings
        proxy.backend = self
    }

    var isEnabled: Bool { settings[SmartHomeSettings.homeKitEnabled] }

    var isConfigured: Bool {
        access == .authorized && !(accessories.isEmpty && scenes.isEmpty && cameras.isEmpty)
    }

    var status: BackendStatus {
        switch access {
        case .notRequested: .notConfigured
        case .waiting: .connecting
        case .authorized: homes.isEmpty ? .failed("No homes in Apple Home") : .connected(detail: selectedHomeName)
        case .denied: .failed("Access was turned off in Settings")
        case .restricted: .failed("Restricted on this iPad")
        }
    }

    func start() {
        if isEnabled { connect() }
    }

    /// Asks for HomeKit access (the system prompt) and starts loading homes.
    func connect() {
        settings[SmartHomeSettings.homeKitEnabled] = true
        guard manager == nil else { return }
        access = .waiting
        let manager = HMHomeManager()
        manager.delegate = proxy
        self.manager = manager
        onChange?()
    }

    /// Stops using Apple Home. The system permission stays as the person set it.
    func disconnect() {
        settings[SmartHomeSettings.homeKitEnabled] = false
        manager?.delegate = nil
        manager = nil
        access = .notRequested
        homes = []
        directory = nil
        clear()
    }

    /// Shows Apple's own setup sheet for HomeKit and Matter accessories, adding to the selected home.
    func addAccessory() async throws {
        let request = HMAccessorySetupRequest()
        request.homeUniqueIdentifier = selectedHome?.uniqueIdentifier
        _ = try await HMAccessorySetupManager().performAccessorySetup(using: request)
        reload()
    }

    func selectHome(_ id: String) {
        settings[SmartHomeSettings.homeKitHomeID] = id
        reload()
        Task { await refresh() }
    }

    /// The home picked in Settings, or the first one.
    var selectedHome: HMHome? {
        guard let homes = manager?.homes, !homes.isEmpty else { return nil }
        let id = settings[SmartHomeSettings.homeKitHomeID]
        return homes.first { $0.uniqueIdentifier.uuidString == id } ?? homes.first
    }

    /// The unit temperatures are shown and set in, from the iPad's region.
    var temperatureUnit: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    // MARK: Delegate callbacks

    func homesDidUpdate() {
        guard let manager else { return }
        let status = manager.authorizationStatus
        if status.contains(.authorized) {
            access = .authorized
        } else if status.contains(.restricted) {
            access = .restricted
        } else if status.contains(.determined) {
            access = .denied
        }
        homes = manager.homes.map { HomeKitHomeSummary(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
        reload()
        // What HomeKit has cached can be missing or stale (a lock locked by hand), so read the home itself.
        Task { await refresh() }
    }

    /// Rebuilds every accessory, camera and scene of the selected home.
    func reload() {
        updateDirectory()
        guard let home = selectedHome else {
            clear()
            return
        }
        home.delegate = proxy
        selectedHomeName = home.name
        var newAccessories: [HomeAccessory] = []
        var newCameras: [HomeCamera] = []
        services = [:]
        cameraProfiles = [:]
        for accessory in home.accessories {
            accessory.delegate = proxy
            for service in accessory.services where HomeKitServiceMapper.kind(forServiceType: service.serviceType) != nil {
                let model = makeAccessory(service: service, accessory: accessory)
                services[model.id] = service
                newAccessories.append(model)
                enableNotifications(for: service)
            }
            let isDoorbell = accessory.services.contains { $0.serviceType == HMServiceTypeDoorbell }
            for profile in accessory.cameraProfiles ?? [] {
                let id = BackendID.make(.homeKit, profile.uniqueIdentifier.uuidString)
                cameraProfiles[id] = profile
                newCameras.append(HomeCamera(id: id, name: accessory.name, room: accessory.room?.name, backend: .homeKit, isDoorbell: isDoorbell))
            }
        }
        let groupModels = groups(in: home, linking: &newAccessories)
        newAccessories += groupModels
        actionSets = [:]
        scenes = home.actionSets.filter { $0.actionSetType != HMActionSetTypeTriggerOwned }.map { set in
            let id = BackendID.make(.homeKit, set.uniqueIdentifier.uuidString)
            actionSets[id] = set
            return HomeScene(id: id, name: set.name, backend: .homeKit, systemImage: Self.symbol(for: set))
        }
        accessories = newAccessories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cameras = newCameras
        onChange?()
    }

    func characteristicDidUpdate(_ characteristic: HMCharacteristic, service: HMService, accessory: HMAccessory) {
        let id = BackendID.make(.homeKit, service.uniqueIdentifier.uuidString)
        if characteristic.characteristicType == HMCharacteristicTypeInputEvent,
           service.serviceType == HMServiceTypeDoorbell || id == doorbellTriggerID() {
            let camera = accessory.cameraProfiles?.first.map { BackendID.make(.homeKit, $0.uniqueIdentifier.uuidString) }
            log.info("Doorbell pressed")
            onDoorbell?(camera)
        }
        updateAccessory(id: id)
    }

    /// Re-reads one service's cached values after a notification or a write.
    func updateAccessory(id: String) {
        guard let service = services[id], let accessory = service.accessory,
              let index = accessories.firstIndex(where: { $0.id == id }) else { return }
        var updated = makeAccessory(service: service, accessory: accessory)
        updated.groupID = accessories[index].groupID
        accessories[index] = updated
        if let groupID = updated.groupID { refreshGroup(groupID) }
        onChange?()
    }

    /// Apple Home groups ("Group with Other Accessories"): one accessory per group,
    /// with each member marked so lists show the group in its place.
    private func groups(in home: HMHome, linking accessories: inout [HomeAccessory]) -> [HomeAccessory] {
        groupNames = [:]
        var result: [HomeAccessory] = []
        for group in home.serviceGroups {
            let id = BackendID.make(.homeKit, group.uniqueIdentifier.uuidString)
            let memberIDs = Set(group.services.map { BackendID.make(.homeKit, $0.uniqueIdentifier.uuidString) })
            // A service in two groups shows in the first one.
            for index in accessories.indices where memberIDs.contains(accessories[index].id) && accessories[index].groupID == nil {
                accessories[index].groupID = id
            }
            let members = accessories.filter { $0.groupID == id }
            guard let model = AccessoryGroups.group(id: id, name: group.name, backend: .homeKit, members: members) else { continue }
            groupNames[id] = group.name
            result.append(model)
        }
        return result
    }

    /// Rebuilds a group's state after one of its members changed.
    private func refreshGroup(_ id: String) {
        guard let name = groupNames[id], let index = accessories.firstIndex(where: { $0.id == id }),
              let model = AccessoryGroups.group(id: id, name: name, backend: .homeKit, members: accessories.filter { $0.groupID == id })
        else { return }
        accessories[index] = model
    }

    /// Rebuilds the directory of every home once HomeKit has loaded them. No
    /// homes yet is taken as still loading, so a restart never shares an empty
    /// directory over a full one.
    private func updateDirectory() {
        guard access == .authorized, let manager, !manager.homes.isEmpty else { return }
        let next = HomeKitDirectoryBuilder.directory(homes: manager.homes)
        if next != directory { directory = next }
    }

    private func clear() {
        selectedHomeName = nil
        services = [:]
        cameraProfiles = [:]
        actionSets = [:]
        groupNames = [:]
        accessories = []
        scenes = []
        cameras = []
        onChange?()
    }

    private func makeAccessory(service: HMService, accessory: HMAccessory) -> HomeAccessory {
        let kind = HomeKitServiceMapper.kind(forServiceType: service.serviceType) ?? .other
        let values = HomeKitValues(service: service)
        var state = HomeKitServiceMapper.state(serviceType: service.serviceType, kind: kind, values: values, unit: temperatureUnit)
        state.isReachable = accessory.isReachable
        let types = Set(service.characteristics.map(\.characteristicType))
        return HomeAccessory(
            id: BackendID.make(.homeKit, service.uniqueIdentifier.uuidString),
            name: service.name.isEmpty ? accessory.name : service.name,
            room: accessory.room?.name,
            kind: kind,
            backend: .homeKit,
            capabilities: HomeKitServiceMapper.capabilities(kind: kind, characteristicTypes: types),
            state: state,
            deviceClass: HomeKitServiceMapper.deviceClass(forServiceType: service.serviceType)
        )
    }

    private func enableNotifications(for service: HMService) {
        for characteristic in service.characteristics
        where characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) && !characteristic.isNotificationEnabled {
            characteristic.enableNotification(true) { _ in }
        }
    }

    private static func symbol(for set: HMActionSet) -> String {
        switch set.actionSetType {
        case HMActionSetTypeWakeUp: "sun.horizon.fill"
        case HMActionSetTypeSleep: "moon.stars.fill"
        case HMActionSetTypeHomeDeparture: "figure.walk.departure"
        case HMActionSetTypeHomeArrival: "house.fill"
        default: SceneSymbol.symbol(icon: nil, name: set.name) ?? "sparkles"
        }
    }
}
