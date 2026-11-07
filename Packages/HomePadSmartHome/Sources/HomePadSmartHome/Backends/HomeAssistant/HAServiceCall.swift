import Foundation
import HAKit
import HomePadCore

/// One Home Assistant service call, such as `light.turn_on` with `brightness_pct: 70`.
struct HAServiceCall: Equatable, Sendable {
    var domain: String
    var service: String
    var data: [String: JSONValue]
    /// Target entity. Nil for raw calls that carry their own target in `data`.
    var entityID: String?

    init(domain: String, service: String, data: [String: JSONValue] = [:], entityID: String? = nil) {
        self.domain = domain
        self.service = service
        self.data = data
        self.entityID = entityID
    }

    /// The `call_service` WebSocket command for HAKit.
    var request: HARequest {
        var payload: [String: Any] = [
            "domain": domain,
            "service": service,
            "service_data": JSONValue.object(data).foundationValue,
        ]
        if let entityID { payload["target"] = ["entity_id": entityID] }
        return HARequest(type: .callService, data: payload, shouldRetry: false)
    }

    /// Entity IDs this call affects, from the target or from `entity_id` in the data.
    var targetEntityIDs: [String] {
        if let entityID { return [entityID] }
        switch data["entity_id"] {
        case .string(let id): return [id]
        case .array(let ids): return ids.compactMap(\.stringValue)
        default: return []
        }
    }
}
