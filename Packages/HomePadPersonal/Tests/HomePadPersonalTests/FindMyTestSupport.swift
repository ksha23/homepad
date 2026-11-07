import Foundation
import HomePadCore
@testable import HomePadPersonal

/// A smart home that only has trackers, standing in for the Smart Home module's
/// Home Assistant backend. It records Play Sound calls and can fail them.
@MainActor
final class FakeTrackerSmartHome: SmartHomeService {
    var accessories: [HomeAccessory] = []
    var scenes: [HomeScene] = []
    var cameras: [HomeCamera] = []
    var connectedBackends: Set<SmartHomeBackend> = [.homeAssistant]
    var favoriteAccessoryIDs: [HomeAccessory.ID] = []
    var trackedDevices: [TrackedDevice] = []
    var zones: [HomeZone] = []
    private(set) var rung: [TrackedDevice.ID] = []
    var failure: SmartHomeError?

    func refresh() async {}
    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws {}
    func activateScene(_ sceneID: HomeScene.ID) async throws {}
    func snapshot(cameraID: HomeCamera.ID) async throws -> Data? { nil }
    func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {}

    func playSound(onTrackedDevice id: TrackedDevice.ID) async throws {
        if let failure { throw failure }
        rung.append(id)
    }
}

/// A household of Kyle (admin), Sam and Jordan, with Kyle's, Sam's and a shared device.
@MainActor
struct FindMyFixture {
    let services: AppServices
    let smartHome = FakeTrackerSmartHome()
    let findMy: FindMyService
    let kyle = HouseholdMember(name: "Kyle", colorHex: "#0A84FF", isAdmin: true)
    let sam = HouseholdMember(name: "Sam Rivera", colorHex: "#FFD60A")
    let jordan = HouseholdMember(name: "Jordan", colorHex: "#30D158")
    static var now: Date { Date() }

    init() {
        services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.findmy.\(UUID().uuidString)")!))
        services.settings[PersonalSettings.demoData] = false
        services.smartHome = smartHome
        for member in [kyle, sam, jordan] { services.household.add(member) }
        smartHome.trackedDevices = Self.devices
        smartHome.zones = [HomeZone(id: "ha:zone.home", name: "Maple Street", latitude: 43.0747, longitude: -89.3842, radius: 100, isHome: true)]
        findMy = FindMyService(services: services, addresses: FindMyAddressBook { _, _ in "120 State St, Madison" })
    }

    static let devices: [TrackedDevice] = [
        TrackedDevice(id: "ha:device_tracker.kyles_iphone", name: "Kyle\u{2019}s iPhone", source: .iCloud, integration: "icloud",
                      model: "iPhone 17 Pro", place: .home, latitude: 43.0748, longitude: -89.3841, accuracy: 12,
                      batteryLevel: 0.82, isCharging: false, lastUpdated: now.addingTimeInterval(-120), ownerName: "Kyle"),
        TrackedDevice(id: "ha:device_tracker.kyles_ipad", name: "Kyle\u{2019}s iPad", source: .companionApp, integration: "mobile_app",
                      model: "iPad16,3", place: .away, latitude: 43.0745, longitude: -89.3925, accuracy: 35,
                      batteryLevel: 0.62, isCharging: true, lastUpdated: now.addingTimeInterval(-600)),
        TrackedDevice(id: "ha:device_tracker.sams_iphone", name: "Sam's iPhone", source: .iCloud, integration: "icloud",
                      model: "iPhone 16", place: .zone("Work"), latitude: 43.0767, longitude: -89.4123, accuracy: 25,
                      batteryLevel: 0.34, isCharging: true, lastUpdated: now.addingTimeInterval(-300), ownerName: "Sam Rivera"),
        TrackedDevice(id: "ha:device_tracker.jordans_phone", name: "Jordan's Phone", source: .other, integration: "life360",
                      place: .away, latitude: 43.0610, longitude: -89.4010, lastUpdated: now.addingTimeInterval(-60)),
        TrackedDevice(id: "ha:device_tracker.living_room_ipad", name: "Living Room iPad", source: .companionApp,
                      integration: "mobile_app", place: .home, latitude: 43.0747, longitude: -89.3842,
                      lastUpdated: now.addingTimeInterval(-3600)),
    ]

    func recognize(_ member: HouseholdMember) {
        services.household.recognize(member.id)
    }

    func titles() -> [String] {
        findMy.visibleDevices.map(\.title)
    }
}
