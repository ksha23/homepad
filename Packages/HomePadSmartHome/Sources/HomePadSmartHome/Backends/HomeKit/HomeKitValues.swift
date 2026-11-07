import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// Characteristic values of one HomeKit service, keyed by characteristic type.
/// HomeKit hands values back as `NSNumber`, so this reads them as numbers.
struct HomeKitValues {
    var raw: [String: Any]

    init(_ raw: [String: Any]) {
        self.raw = raw
    }

    init(service: HMService) {
        var raw: [String: Any] = [:]
        for characteristic in service.characteristics {
            if let value = characteristic.value { raw[characteristic.characteristicType] = value }
        }
        self.raw = raw
    }

    var types: Set<String> { Set(raw.keys) }

    func double(_ type: String) -> Double? { (raw[type] as? NSNumber)?.doubleValue }
    func int(_ type: String) -> Int? { (raw[type] as? NSNumber)?.intValue }
    func bool(_ type: String) -> Bool? { (raw[type] as? NSNumber)?.boolValue }
}
