import Foundation
import HomePadCore

/// Registering with Home Assistant's `mobile_app` integration, the way the
/// Home Assistant app does, so each HomePad is a device with sensors and a
/// notify action.
///
/// - `POST /api/mobile_app/registrations` with the long-lived token answers with
///   a webhook ID. Everything after that goes to `POST /api/webhook/<id>`.
/// - Home Assistant tells registrations apart by `app_id` and `device_id`
///   together, and registering the same pair again replaces the old one. The
///   device ID is made once and kept on the iPad, so registering again never
///   makes a second device.
/// - `app_data.push_websocket_channel` asks for notifications over the
///   WebSocket (`mobile_app/push_notification_channel`). There is no push server.
/// - Encryption is off. The webhook stays on the home network, like the token.
enum MobileAppRegistration {
    /// What HomePad keeps after registering. The webhook ID is a credential, so
    /// it lives in the keychain and is never logged.
    struct Stored: Codable, Equatable, Sendable {
        var webhookID: String
        /// The Home Assistant address it was made with. Another address registers
        /// again, which replaces the device when it is the same Home Assistant.
        var instanceURL: String
        /// The name Home Assistant has, so a new room renames the device.
        var deviceName: String
        var appVersion: String
        var registeredAt: Date
    }

    /// Notifications come over the WebSocket only.
    static let appData: JSONValue = ["push_websocket_channel": true]

    /// The body of `POST /api/mobile_app/registrations`.
    static func body(deviceID: String, deviceName: String, info: MobileAppDeviceInfo) -> JSONValue {
        [
            "app_id": .string(info.appID),
            "app_name": .string(info.appName),
            "app_version": .string(info.appVersion),
            "device_id": .string(deviceID),
            "device_name": .string(deviceName),
            "manufacturer": .string(info.manufacturer),
            "model": .string(info.model),
            "os_name": .string(info.osName),
            // Without it Home Assistant accepts the registration but setting it up fails.
            "os_version": .string(info.osVersion),
            "supports_encryption": false,
            "app_data": appData,
        ]
    }

    /// The `update_registration` webhook message, for a new name or version.
    static func updateMessage(deviceName: String, info: MobileAppDeviceInfo) -> JSONValue {
        [
            "type": "update_registration",
            "data": [
                "app_version": .string(info.appVersion),
                "device_name": .string(deviceName),
                "manufacturer": .string(info.manufacturer),
                "model": .string(info.model),
                "os_version": .string(info.osVersion),
                // It replaces the app data, so push over the WebSocket is asked for again.
                "app_data": appData,
            ],
        ]
    }

    /// The webhook ID from the registration's answer. The cloudhook and remote
    /// addresses are not used: HomePad talks to Home Assistant on the home network.
    static func webhookID(from response: JSONValue) throws -> String {
        guard let id = response["webhook_id"]?.stringValue, !id.isEmpty else {
            throw SmartHomeError.backend("Home Assistant did not answer the registration with a webhook.")
        }
        return id
    }

    /// The config entry Home Assistant made for this device, found in the device
    /// registry by the device ID, so Remove can delete it.
    static func configEntryID(deviceID: String, deviceRegistry: JSONValue) -> String? {
        for device in deviceRegistry.arrayValue ?? [] {
            let identifiers = device["identifiers"]?.arrayValue ?? []
            let isOurs = identifiers.contains { pair in
                pair.arrayValue?.compactMap(\.stringValue) == ["mobile_app", deviceID]
            }
            guard isOurs else { continue }
            return device["primary_config_entry"]?.stringValue
                ?? device["config_entries"]?.arrayValue?.first?.stringValue
        }
        return nil
    }
}
