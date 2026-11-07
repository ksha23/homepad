import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// Commands: reading values again, writing characteristics, groups and scenes.
extension HomeKitBackend {
    /// Reads every accessory's values again and shows each one as soon as it is in. HomeKit only
    /// hands out what it has cached, which for some accessories is missing or stale until they
    /// change, so the home is read like this as it loads. Accessories are read side by side, so
    /// one that is slow or out of reach holds up only itself.
    func refresh() async {
        await withTaskGroup(of: String.self) { group in
            for (id, service) in services {
                group.addTask {
                    for characteristic in service.characteristics
                    where characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                        try? await characteristic.readValue()
                    }
                    return id
                }
            }
            for await id in group { updateAccessory(id: id) }
        }
    }

    func perform(_ command: AccessoryCommand, on accessory: HomeAccessory) async throws {
        if accessory.isGroup {
            try await performOnGroup(command, group: accessory)
            return
        }
        guard let service = services[accessory.id] else { throw SmartHomeError.accessoryNotFound(accessory.id) }
        let target = HomeKitCommandMapper.Target(
            serviceType: service.serviceType, kind: accessory.kind, state: accessory.state,
            characteristicTypes: Set(service.characteristics.map(\.characteristicType)), unit: temperatureUnit
        )
        for write in try HomeKitCommandMapper.writes(for: command, target: target) {
            guard let characteristic = service.characteristics.first(where: { $0.characteristicType == write.characteristicType }) else { continue }
            do {
                try await characteristic.writeValue(write.value)
            } catch {
                throw SmartHomeError.backend("\(accessory.name) did not respond. \(error.localizedDescription)")
            }
        }
        // HomeKit does not notify the app about its own writes.
        updateAccessory(id: accessory.id)
    }

    /// Sends a command to every member at once, as Apple Home does for a group.
    private func performOnGroup(_ command: AccessoryCommand, group: HomeAccessory) async throws {
        let members = accessories.filter { $0.groupID == group.id }
        let memberCommand = AccessoryGroups.memberCommand(command, group: group)
        let failed = await withTaskGroup(of: String?.self) { tasks in
            for member in members {
                tasks.addTask { @MainActor in
                    do {
                        try await self.perform(memberCommand, on: member)
                        return nil
                    } catch {
                        return member.name
                    }
                }
            }
            var names: [String] = []
            for await name in tasks { if let name { names.append(name) } }
            return names
        }
        guard failed.isEmpty else {
            throw SmartHomeError.backend("\(ListFormatter.localizedString(byJoining: failed.sorted())) did not respond.")
        }
    }

    func activateScene(_ scene: HomeScene) async throws {
        guard let set = actionSets[scene.id], let home = selectedHome else { throw SmartHomeError.accessoryNotFound(scene.id) }
        try await home.executeActionSet(set)
    }
}
