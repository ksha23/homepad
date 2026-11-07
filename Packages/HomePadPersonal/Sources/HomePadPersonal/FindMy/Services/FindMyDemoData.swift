import Foundation
import HomePadCore

/// Demo devices for the simulator and screenshots, shown while Personal's demo
/// data is on (`PersonalSettings.demoData`). They sit around Madison, the demo
/// weather's city, and belong to the household's first three members (Alex,
/// Sam and Jordan with `-HomePadDemoContent`). Nothing moves, so the map is still.
enum FindMyDemoData {
    static let homeZone = HomeZone(id: "demo:zone.home", name: "Home", latitude: 43.0747, longitude: -89.3842,
                                   radius: 120, isHome: true)
    static let workZone = HomeZone(id: "demo:zone.work", name: "Work", latitude: 43.0753, longitude: -89.4040, radius: 200)
    static let zones = [homeZone, workZone]

    /// Fixed addresses for the demo spots, so screenshots need no network.
    static let addresses: [String: String] = [
        FindMyAddressBook.key(43.0745, -89.3925): "State St, Madison",
        FindMyAddressBook.key(43.0718, -89.3800): "John Nolen Dr, Madison",
        FindMyAddressBook.key(43.0749, -89.3844): "Capitol Square, Madison",
        FindMyAddressBook.key(43.0754, -89.4038): "Bascom Hill, Madison",
        FindMyAddressBook.key(43.0744, -89.3839): "Capitol Square, Madison",
        FindMyAddressBook.key(43.0747, -89.3842): "Capitol Square, Madison",
    ]

    static func address(latitude: Double, longitude: Double) -> String? {
        addresses[FindMyAddressBook.key(latitude, longitude)]
    }

    /// - Parameters:
    ///   - members: The household. The first three own the demo devices.
    ///   - now: When the demo started, so "last seen" times stay put.
    static func devices(members: [HouseholdMember], now: Date) -> [TrackedDevice] {
        let names = members.prefix(3).map { String($0.name.split(separator: " ").first ?? "") }
        let first = names.indices.contains(0) ? names[0] : "Alex"
        let second = names.indices.contains(1) ? names[1] : "Sam"
        let third = names.indices.contains(2) ? names[2] : "Jordan"
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            TrackedDevice(id: "demo:device_tracker.iphone_1", name: "\(first)'s iPhone", source: .iCloud, integration: "icloud",
                          model: "iPhone 17 Pro", place: .home, latitude: 43.0749, longitude: -89.3844, accuracy: 10,
                          batteryLevel: 0.82, isCharging: false, lastUpdated: ago(2), ownerName: first),
            TrackedDevice(id: "demo:device_tracker.watch_1", name: "\(first)'s Apple Watch", source: .iCloud, integration: "icloud",
                          model: "Apple Watch Series 11", place: .away, latitude: 43.0745, longitude: -89.3925, accuracy: 35,
                          batteryLevel: 0.41, isCharging: false, lastUpdated: ago(14), ownerName: first),
            TrackedDevice(id: "demo:device_tracker.iphone_2", name: "\(second)'s iPhone", source: .iCloud, integration: "icloud",
                          model: "iPhone 16", place: .zone(workZone.name), latitude: 43.0754, longitude: -89.4038, accuracy: 18,
                          batteryLevel: 0.34, isCharging: true, lastUpdated: ago(5), ownerName: second),
            TrackedDevice(id: "demo:device_tracker.ipad_2", name: "\(second)'s iPad", source: .companionApp, integration: "mobile_app",
                          model: "iPad Air", place: .home, latitude: 43.0744, longitude: -89.3839, accuracy: 25,
                          batteryLevel: 0.67, isCharging: false, lastUpdated: ago(40)),
            TrackedDevice(id: "demo:device_tracker.phone_3", name: "\(third)'s Phone", source: .other, integration: "life360",
                          place: .away, latitude: 43.0718, longitude: -89.3800, accuracy: 20,
                          batteryLevel: 0.51, lastUpdated: ago(1)),
            TrackedDevice(id: "demo:device_tracker.kitchen_ipad", name: "Kitchen iPad", source: .companionApp, integration: "mobile_app",
                          model: "iPad Pro", place: .home, latitude: 43.0747, longitude: -89.3842, accuracy: 15,
                          batteryLevel: 1, isCharging: true, lastUpdated: ago(3)),
        ]
    }
}
