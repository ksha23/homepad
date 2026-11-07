import Foundation
import HomePadCore
@testable import HomePadSmartHome

/// Stands in for Home Assistant's `mobile_app` HTTP endpoints. Records what was
/// sent and answers the way Home Assistant does, so nothing reaches a network.
@MainActor
final class FakeMobileAppTransport: MobileAppTransport {
    /// Registration bodies, in order.
    private(set) var registrations: [JSONValue] = []
    /// Webhook messages with the webhook they went to, in order.
    private(set) var messages: [(webhookID: String, message: JSONValue)] = []
    private(set) var deletedEntries: [String] = []
    /// Webhooks Home Assistant has deleted (answers 410).
    var goneWebhooks: Set<String> = []
    private var registrationCount = 0

    func register(_ body: JSONValue, on configuration: HomeAssistantConfiguration) async throws -> JSONValue {
        registrations.append(body)
        registrationCount += 1
        // The recorded answer for the first, a new webhook for each one after.
        guard registrationCount > 1 else { return Fixtures.json("rest_mobile_app_registration") }
        return ["webhook_id": .string("fake-webhook-\(registrationCount)"), "secret": nil, "cloudhook_url": nil]
    }

    func send(_ message: JSONValue, webhookID: String, on configuration: HomeAssistantConfiguration) async throws -> MobileAppWebhookReply {
        messages.append((webhookID, message))
        guard !goneWebhooks.contains(webhookID) else { return .gone }
        switch message["type"]?.stringValue {
        case "register_sensor":
            return .handled(["success": true])
        case "update_sensor_states":
            // Every sensor in the request is taken.
            var results: [String: JSONValue] = [:]
            for sensor in message["data"]?.arrayValue ?? [] {
                if let id = sensor["unique_id"]?.stringValue { results[id] = ["success": true] }
            }
            return .handled(.object(results))
        default:
            return .handled([:])
        }
    }

    func deleteConfigEntry(_ entryID: String, on configuration: HomeAssistantConfiguration) async throws {
        deletedEntries.append(entryID)
    }

    /// Webhook messages of one type.
    func messages(ofType type: String) -> [JSONValue] {
        messages.map(\.message).filter { $0["type"]?.stringValue == type }
    }
}

extension MobileAppDeviceInfo {
    static let test = MobileAppDeviceInfo(appID: "com.ksha23.homepad", appName: "HomePad", appVersion: "1.4",
                                          manufacturer: "Apple", model: "iPad16,3", osName: "iPadOS", osVersion: "26.1")
}

extension MobileAppSensorInputs {
    /// Someone at the iPad on the face, with every reading known.
    static let sample = MobileAppSensorInputs(
        presence: PresenceSnapshot(isSomeonePresent: true, peopleCount: 1, proximity: .mid, nearestDistanceMeters: 1.6,
                                   ambientLight: .normal, source: .trueDepth, ambientLux: 212.4),
        recognizedName: "Kyle",
        display: .ambient,
        kiosk: KioskStatus(surface: .face, faceID: "faces.modular", brightness: 0.62, batteryLevel: 0.8, power: .charging),
        faceTitle: "Modular",
        appID: nil,
        appTitle: nil
    )
}
