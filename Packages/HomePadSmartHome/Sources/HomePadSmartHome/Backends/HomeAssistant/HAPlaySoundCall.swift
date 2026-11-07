import Foundation
import HomePadCore

/// The Home Assistant action that makes a tracked device play a sound.
///
/// - iCloud trackers: `icloud.play_sound` with the Apple Account (`account`, the
///   iCloud config entry's title, which is its username) and the device's name as
///   Find My shows it (`device_name`). Home Assistant compares names without
///   spaces, case or punctuation. The tracker's `device_name` attribute is not
///   that name: it holds the model, such as "iPhone 15 Pro".
/// - Companion app trackers: `notify.mobile_app_<device>` with a critical sound,
///   which plays at full volume even when the phone is silenced or in Focus.
enum HAPlaySoundCall {
    /// The notification text a Companion app device shows while it rings.
    static let title = "Find My"
    static let message = "HomePad is playing a sound to help find this device."

    /// Builds the call for one tracker.
    /// - Parameters:
    ///   - entityID: The tracker, for example `device_tracker.kyles_iphone`.
    ///   - state: Its current state, for its name when the registry has none.
    ///   - registry: For the integration, the config entry and the device's registered name.
    ///   - iCloudAccounts: The iCloud integration's config entries (`config_entries/get`),
    ///     needed only for iCloud trackers.
    static func call(entityID: String, state: HAState?, registry: HARegistry,
                     iCloudAccounts: [SmartHomeIntegrationEntry] = []) throws -> HAServiceCall {
        let name = state.map { HAStateMapper.displayName(of: $0, registry: registry) } ?? HAStateMapper.humanized(entityID)
        switch registry.platform(of: entityID) {
        case "icloud":
            let account = try account(for: entityID, registry: registry, entries: iCloudAccounts, deviceName: name)
            // The device registry keeps iCloud's own name even after a rename in Home Assistant.
            let deviceName = registeredDeviceName(of: entityID, registry: registry) ?? state?.friendlyName ?? name
            return HAServiceCall(domain: "icloud", service: "play_sound", data: [
                "account": .string(account),
                "device_name": .string(deviceName),
            ])
        case "mobile_app":
            guard let deviceName = registeredDeviceName(of: entityID, registry: registry) else {
                throw SmartHomeError.backend("Home Assistant does not say which Companion app device \(name) is.")
            }
            return HAServiceCall(domain: "notify", service: notifyService(forDeviceNamed: deviceName), data: criticalSound)
        default:
            throw cannotRing(name)
        }
    }

    /// Why a tracker from another integration, such as Life360, cannot ring.
    static func cannotRing(_ name: String) -> SmartHomeError {
        .backend("\(name) cannot play a sound. Only devices from the iCloud integration or the Companion app can.")
    }

    /// `notify` data that rings with a critical sound. `push` is for iPhone and
    /// iPad. `ttl`, `priority` and `channel` make Android ring as an alarm.
    static var criticalSound: [String: JSONValue] {
        [
            "title": .string(title),
            "message": .string(message),
            "data": [
                "push": [
                    "sound": ["name": "default", "critical": 1, "volume": 1.0],
                ],
                "ttl": 0,
                "priority": "high",
                "channel": "alarm_stream",
            ],
        ]
    }

    /// `mobile_app_kyle_s_iphone` for "Kyle's iPhone", the name the Companion app
    /// registered with. Home Assistant names the action after it, slugified.
    static func notifyService(forDeviceNamed name: String) -> String {
        "mobile_app_" + slug(name)
    }

    /// Home Assistant's `slugify`: Latin letters without accents, lowercased, and
    /// every run of anything else turned into one underscore.
    static func slug(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let folded = latin.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        var pendingSeparator = false
        for scalar in folded.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingSeparator, !slug.isEmpty { slug.append("_") }
                pendingSeparator = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return slug.isEmpty ? "unknown" : slug
    }

    /// The name the tracker's device registered with, before any rename.
    static func registeredDeviceName(of entityID: String, registry: HARegistry) -> String? {
        registry.deviceID(for: entityID).flatMap { registry.devices[$0]?.registeredName }
    }

    /// The Apple Account an iCloud tracker belongs to: its own config entry, or
    /// the only iCloud account there is.
    static func account(for entityID: String, registry: HARegistry, entries: [SmartHomeIntegrationEntry],
                        deviceName: String) throws -> String {
        let accounts = entries.filter { $0.domain == "icloud" }
        if let entryID = registry.entities[entityID]?.configEntryID,
           let entry = accounts.first(where: { $0.entryID == entryID }) {
            return entry.title
        }
        if accounts.count == 1, let only = accounts.first { return only.title }
        if accounts.isEmpty {
            throw SmartHomeError.backend("The iCloud integration is not set up in Home Assistant.")
        }
        throw SmartHomeError.backend("Home Assistant has more than one iCloud account and HomePad could not tell which one has \(deviceName).")
    }
}
