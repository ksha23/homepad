import Foundation
import HAKit
import HomePadCore

/// One Home Assistant entity state, with typed attribute access.
/// Built from HAKit's `HAEntity`, which does the wire decoding.
struct HAState: Hashable, Sendable {
    var entityID: String
    var state: String
    var attributes: [String: JSONValue]
    var lastChanged: Date
    /// When the state or any attribute last changed, such as a tracker's
    /// coordinates. `lastChanged` only moves with the state itself.
    var lastUpdated: Date

    init(entityID: String, state: String, attributes: [String: JSONValue] = [:], lastChanged: Date = Date(),
         lastUpdated: Date? = nil) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated ?? lastChanged
    }

    init(entity: HAEntity) {
        self.init(
            entityID: entity.entityId,
            state: entity.state,
            attributes: entity.attributes.dictionary.mapValues { JSONValue(foundation: $0) },
            lastChanged: entity.lastChanged,
            lastUpdated: entity.lastUpdated
        )
    }

    /// `light` for `light.kitchen`.
    var domain: String { Self.domain(of: entityID) }

    static func domain(of entityID: String) -> String {
        String(entityID.prefix { $0 != "." })
    }

    var isUnavailable: Bool { state == "unavailable" }
    var isUnknown: Bool { state == "unknown" }

    subscript(attribute: String) -> JSONValue? { attributes[attribute] }

    var friendlyName: String? { attributes["friendly_name"]?.stringValue }
    var deviceClass: String? { attributes["device_class"]?.stringValue }
    var supportedFeatures: Int { attributes["supported_features"]?.intValue ?? 0 }

    func supports(_ feature: Int) -> Bool { supportedFeatures & feature != 0 }

    /// The numeric state, for sensors.
    var numericState: Double? {
        guard !isUnavailable, !isUnknown else { return nil }
        return Double(state)
    }
}
