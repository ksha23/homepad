import CoreBluetooth
import Foundation
import HomePadCore

/// On a phone: stays connected over Bluetooth to the HomePads nearby that
/// offer `ProximityWake.service`, and wakes the app when one notifies `wake`.
///
/// The central manager has a restore identifier, so iOS keeps scanning and
/// connecting for the app after it ends it, and relaunches the app in the
/// background for a connection or a notification. iOS does not relaunch an
/// app the person force quit, or after they turn Bluetooth off in Settings,
/// until it is opened again (TN3115).
@MainActor
final class PhoneWakeListener: NSObject, WakeListening {
    var onWake: @MainActor () -> Void = {}
    private(set) var problem: String?

    private var central: CBCentralManager?
    private var tags: [Data] = []
    /// HomePads found or restored, by Core Bluetooth's identifier.
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// Each HomePad's `hello`, once found, so new tags reach it.
    private var helloCharacteristics: [UUID: CBCharacteristic] = [:]
    /// A HomePad's address changes now and then, so the same iPad can turn up
    /// under a new identifier. Old ones are let go past this many.
    private let maxPeripherals = 8
    private let log = Log.make("PhoneVisit")

    func listen(tags: [Data]) {
        self.tags = tags
        guard central == nil else {
            resume()
            peripherals.values.forEach(writeTags)
            return
        }
        // Making the manager is what asks for Bluetooth the first time.
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: ProximityWake.restoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: false,
        ])
    }

    func stop() {
        guard let central else { return }
        if central.state == .poweredOn {
            central.stopScan()
            peripherals.values.forEach(central.cancelPeripheralConnection)
        }
        peripherals = [:]
        helloCharacteristics = [:]
        self.central = nil
    }

    /// Scans for HomePads and keeps a connection waiting for each one known.
    /// A waiting connection never times out, so a HomePad that comes back in
    /// range connects by itself.
    private func resume() {
        guard let central, central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [ProximityWake.service]) {
            adopt(peripheral)
        }
        central.scanForPeripherals(withServices: [ProximityWake.service], options: nil)
        for peripheral in peripherals.values where peripheral.state == .disconnected {
            central.connect(peripheral)
        }
    }

    private func adopt(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
        guard peripherals.count > maxPeripherals,
              let stale = peripherals.values.first(where: { $0.state == .disconnected && $0.identifier != peripheral.identifier }) else { return }
        central?.cancelPeripheralConnection(stale)
        peripherals[stale.identifier] = nil
        helloCharacteristics[stale.identifier] = nil
    }

    private func writeTags(to peripheral: CBPeripheral) {
        guard peripheral.state == .connected, let hello = helloCharacteristics[peripheral.identifier], !tags.isEmpty else { return }
        peripheral.writeValue(tags.reduce(Data(), +), for: hello, type: .withResponse)
    }

    private func stateChanged(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            problem = nil
            resume()
        case .unauthorized:
            problem = "Allow Bluetooth for HomePad in Settings, so your HomePad can wake it."
        case .poweredOff:
            problem = "Turn on Bluetooth so your HomePad can reach this iPhone when HomePad is closed."
        case .unsupported:
            problem = "This device has no Bluetooth, so your HomePad reaches it only while HomePad is open."
        default:
            break
        }
    }
}

extension PhoneWakeListener: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { stateChanged(central.state) }
    }

    /// iOS relaunched the app for a Bluetooth event and hands back what it kept.
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
            restored.forEach(adopt)
            log.info("Restored \(restored.count) HomePad connections")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard peripherals[peripheral.identifier]?.state != .connected else { return }
            adopt(peripheral)
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
            peripheral.discoverServices([ProximityWake.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { reconnect(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { reconnect(peripheral) }
    }

    /// Waits for the HomePad to come back, and scans again in case it comes
    /// back under a new address. A scan reports each HomePad once.
    private func reconnect(_ peripheral: CBPeripheral) {
        helloCharacteristics[peripheral.identifier] = nil
        guard let central, central.state == .poweredOn, peripherals[peripheral.identifier] != nil else { return }
        central.connect(peripheral)
        central.stopScan()
        central.scanForPeripherals(withServices: [ProximityWake.service], options: nil)
    }
}

extension PhoneWakeListener: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == ProximityWake.service }) else { return }
            peripheral.discoverCharacteristics([ProximityWake.wake, ProximityWake.hello], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == ProximityWake.hello {
                    helloCharacteristics[peripheral.identifier] = characteristic
                    writeTags(to: peripheral)
                } else if characteristic.uuid == ProximityWake.wake {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == ProximityWake.wake, error == nil else { return }
            onWake()
        }
    }
}
