import Foundation
@preconcurrency import HomeKit

/// Receives HomeKit's delegate callbacks and hands them to the backend on the main actor.
/// Kept separate so the backend can stay a plain `@Observable` Swift class.
final class HomeKitDelegateProxy: NSObject, HMHomeManagerDelegate, HMHomeDelegate, HMAccessoryDelegate {
    @MainActor weak var backend: HomeKitBackend?

    private func forward(_ work: @escaping @MainActor (HomeKitBackend) -> Void) {
        Task { @MainActor [weak self] in
            if let backend = self?.backend { work(backend) }
        }
    }

    // MARK: HMHomeManagerDelegate

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        forward { $0.homesDidUpdate() }
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        forward { $0.homesDidUpdate() }
    }

    // MARK: HMHomeDelegate

    func home(_ home: HMHome, didAdd accessory: HMAccessory) { forward { $0.reload() } }
    func home(_ home: HMHome, didRemove accessory: HMAccessory) { forward { $0.reload() } }
    func home(_ home: HMHome, didAdd actionSet: HMActionSet) { forward { $0.reload() } }
    func home(_ home: HMHome, didRemove actionSet: HMActionSet) { forward { $0.reload() } }
    func home(_ home: HMHome, didUpdateNameFor actionSet: HMActionSet) { forward { $0.reload() } }
    func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) { forward { $0.reload() } }

    // MARK: HMAccessoryDelegate

    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        forward { $0.characteristicDidUpdate(characteristic, service: service, accessory: accessory) }
    }

    func accessoryDidUpdateReachability(_ accessory: HMAccessory) { forward { $0.reload() } }
    func accessoryDidUpdateServices(_ accessory: HMAccessory) { forward { $0.reload() } }
    func accessoryDidUpdateName(_ accessory: HMAccessory) { forward { $0.reload() } }
    func accessory(_ accessory: HMAccessory, didUpdateNameFor service: HMService) { forward { $0.reload() } }
}
