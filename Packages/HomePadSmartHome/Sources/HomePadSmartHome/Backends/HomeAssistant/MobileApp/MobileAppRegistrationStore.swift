import Foundation
import HomePadCore

/// Keeps this iPad's device ID and its registration. Both stay on this iPad:
/// another HomePad must register as a device of its own.
@MainActor
struct MobileAppRegistrationStore {
    /// The stable device ID, made on first use.
    var deviceID: () -> String
    var load: () -> MobileAppRegistration.Stored?
    var save: (MobileAppRegistration.Stored?) -> Void

    /// The device ID in this iPad's settings and the registration, with its
    /// webhook ID, in a keychain item that does not sync to iCloud Keychain.
    static func live(settings: SettingsStore, service: String) -> MobileAppRegistrationStore {
        let keychain = KeychainStore(service: service, synchronizable: false)
        let account = SmartHomeSettings.homeAssistantDeviceRegistrationAccount
        return MobileAppRegistrationStore(
            deviceID: {
                let existing = settings[SmartHomeSettings.homeAssistantDeviceID]
                if !existing.isEmpty { return existing }
                let made = UUID().uuidString
                settings[SmartHomeSettings.homeAssistantDeviceID] = made
                return made
            },
            load: {
                guard let text = keychain.string(for: account) else { return nil }
                return try? JSONDecoder().decode(MobileAppRegistration.Stored.self, from: Data(text.utf8))
            },
            save: { stored in
                let text = stored.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
                keychain.set(text, for: account)
            }
        )
    }

    /// Keeps everything in memory, for tests and previews.
    static func inMemory(deviceID: String = "test-device", _ initial: MobileAppRegistration.Stored? = nil) -> MobileAppRegistrationStore {
        final class Box { var value: MobileAppRegistration.Stored? }
        let box = Box()
        box.value = initial
        return MobileAppRegistrationStore(deviceID: { deviceID }, load: { box.value }, save: { box.value = $0 })
    }
}
