import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// Builds this HomePad's `HomeKitDirectory` from every home, with the same IDs,
/// names and rooms the backend gives its accessories, groups, cameras and scenes.
@MainActor
enum HomeKitDirectoryBuilder {
    static func directory(homes: [HMHome]) -> HomeKitDirectory {
        HomeKitDirectory(entries: homes.flatMap(entries(in:)))
    }

    private static func entries(in home: HMHome) -> [HomeKitDirectory.Entry] {
        var entries: [HomeKitDirectory.Entry] = []
        for accessory in home.accessories {
            entries += services(of: accessory, home: home.name)
            entries += cameras(of: accessory, home: home.name)
        }
        entries += home.serviceGroups.map { group in
            HomeKitDirectory.Entry(id: id(group.uniqueIdentifier), kind: HomeKitDirectory.Kind.group,
                                   home: home.name, name: group.name)
        }
        entries += home.actionSets.filter { $0.actionSetType != HMActionSetTypeTriggerOwned }.map { set in
            HomeKitDirectory.Entry(id: id(set.uniqueIdentifier), kind: HomeKitDirectory.Kind.scene,
                                   home: home.name, name: set.name)
        }
        return entries
    }

    /// The services the backend shows as accessories, named as it names them.
    private static func services(of accessory: HMAccessory, home: String) -> [HomeKitDirectory.Entry] {
        accessory.services
            .filter { HomeKitServiceMapper.kind(forServiceType: $0.serviceType) != nil }
            .map { service in
                HomeKitDirectory.Entry(
                    id: id(service.uniqueIdentifier), kind: service.serviceType, home: home,
                    room: accessory.room?.name, name: service.name.isEmpty ? accessory.name : service.name,
                    accessory: accessory.name
                )
            }
    }

    private static func cameras(of accessory: HMAccessory, home: String) -> [HomeKitDirectory.Entry] {
        (accessory.cameraProfiles ?? []).map { profile in
            HomeKitDirectory.Entry(id: id(profile.uniqueIdentifier), kind: HomeKitDirectory.Kind.camera,
                                   home: home, room: accessory.room?.name, name: accessory.name)
        }
    }

    private static func id(_ uuid: UUID) -> String {
        BackendID.make(.homeKit, uuid.uuidString)
    }
}
