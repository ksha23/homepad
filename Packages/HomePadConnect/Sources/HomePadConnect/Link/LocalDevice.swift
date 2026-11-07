import Foundation
import HomePadCore

/// This device's identity on the peer link: a stable random ID, its kind and
/// the name other devices see ("Kitchen", "Kyle's iPhone").
@MainActor
public enum LocalDevice {
    /// Stable per install. Created on first use.
    public static func id(settings: SettingsStore) -> String {
        let existing = settings[ConnectSettings.deviceID]
        if !existing.isEmpty { return existing }
        let id = UUID().uuidString
        settings[ConnectSettings.deviceID] = id
        return id
    }

    /// HomePads go by their room. Companions go by their kind.
    public static func name(settings: SettingsStore, kind: DeviceKind) -> String {
        let room = settings[ConnectSettings.roomName].trimmingCharacters(in: .whitespaces)
        if !room.isEmpty { return room }
        return kind.displayName
    }

    /// When HomePad was installed on this device: when iOS made the app's
    /// Documents folder. It stays through updates, so the HomePad set up first
    /// keeps its setup when two that were set up apart first share one.
    static func installedAt() -> Date {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let created = try? FileManager.default.attributesOfItem(atPath: documents.path)[.creationDate] as? Date
        else { return Date() }
        return created
    }

    public static func identity(settings: SettingsStore) -> LocalIdentity {
        let kind = DeviceKind.current
        return LocalIdentity(deviceID: id(settings: settings), name: name(settings: settings, kind: kind), kind: kind)
    }
}
