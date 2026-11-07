import CoreBluetooth
import Foundation
import HomePadCore

/// On a HomePad: offers `ProximityWake.service` over Bluetooth, so the phones
/// that share their photos, calendars or reminders with it stay connected and
/// can be woken.
///
/// It advertises only the service's UUID, never the room or anyone's name,
/// and only while some linked phone shares something, so a household that
/// never turns this on is never asked for Bluetooth. iOS advertises only
/// while the app is in front, which a HomePad always is.
@MainActor
final class HomePadWakeBeacon: NSObject {
    /// Why phones cannot be woken, in words, or nil.
    private(set) var problem: String?

    private var manager: CBPeripheralManager?
    private var wakeCharacteristic: CBMutableCharacteristic?
    /// The tags each connected phone wrote, by Core Bluetooth's identifier.
    private var tagsByCentral: [UUID: Set<Data>] = [:]
    /// Phones subscribed to `wake`.
    private var subscribers: [UUID: CBCentral] = [:]
    /// Wakes that waited for room in Core Bluetooth's queue.
    private var queued: [CBCentral] = []
    private let log = Log.make("PhoneVisit")

    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil else { return }
        // Making the manager is what asks for Bluetooth the first time.
        manager = CBPeripheralManager(delegate: self, queue: .main, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
    }

    func stop() {
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager = nil
        wakeCharacteristic = nil
        tagsByCentral = [:]
        subscribers = [:]
        queued = []
    }

    /// True when a phone that wrote `tag` is connected and listening.
    func canWake(_ tag: Data) -> Bool {
        !centrals(with: tag).isEmpty
    }

    /// Wakes the phone that wrote `tag`. False when it is not connected.
    @discardableResult
    func wake(_ tag: Data) -> Bool {
        let targets = centrals(with: tag)
        guard let manager, let wakeCharacteristic, !targets.isEmpty else { return false }
        if !manager.updateValue(Data([1]), for: wakeCharacteristic, onSubscribedCentrals: targets) {
            queued += targets
        }
        log.info("Woke \(targets.count) phone over Bluetooth")
        return true
    }

    private func centrals(with tag: Data) -> [CBCentral] {
        subscribers.compactMap { id, central in tagsByCentral[id]?.contains(tag) == true ? central : nil }
    }

    private func publish() {
        guard let manager, manager.state == .poweredOn, wakeCharacteristic == nil else { return }
        let wake = CBMutableCharacteristic(type: ProximityWake.wake, properties: [.notify], value: nil, permissions: [])
        let hello = CBMutableCharacteristic(type: ProximityWake.hello, properties: [.write], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: ProximityWake.service, primary: true)
        service.characteristics = [wake, hello]
        wakeCharacteristic = wake
        manager.add(service)
    }

    private func stateChanged(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            problem = nil
            publish()
        case .unauthorized:
            problem = "Allow Bluetooth for HomePad in the iPad's Settings, so it can wake people's iPhones."
        case .poweredOff:
            problem = "Turn on Bluetooth on this iPad, so it can wake people's iPhones."
            wakeCharacteristic = nil
        default:
            break
        }
    }
}

extension HomePadWakeBeacon: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { stateChanged(peripheral.state) }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                log.error("Could not offer the wake service: \(error.localizedDescription, privacy: .public)")
                return
            }
            peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [ProximityWake.service]])
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        MainActor.assumeIsolated {
            for request in requests where request.characteristic.uuid == ProximityWake.hello {
                tagsByCentral[request.central.identifier] = Set(ProximityWake.tags(in: request.value ?? Data()))
            }
            if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        MainActor.assumeIsolated { subscribers[central.identifier] = central }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            subscribers[central.identifier] = nil
            tagsByCentral[central.identifier] = nil
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            guard let wakeCharacteristic, !queued.isEmpty else { return }
            let targets = queued
            queued = []
            if !peripheral.updateValue(Data([1]), for: wakeCharacteristic, onSubscribedCentrals: targets) { queued = targets }
        }
    }
}
