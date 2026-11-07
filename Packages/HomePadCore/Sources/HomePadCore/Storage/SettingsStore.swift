import Foundation
import Observation

/// A typed settings key. Name keys `<module>.<setting>`, for example `audio.autoRoutePrompt`.
public struct SettingKey<Value: Codable> {
    public let name: String
    public let defaultValue: Value
    /// Synced to the user's other devices through iCloud key-value storage.
    public let syncsWithICloud: Bool

    public init(_ name: String, default defaultValue: Value, syncsWithICloud: Bool = false) {
        self.name = name
        self.defaultValue = defaultValue
        self.syncsWithICloud = syncsWithICloud
    }
}

extension SettingKey: Sendable where Value: Sendable {}

/// Non-secret settings. Secrets (API keys, tokens) go in `KeychainStore`.
/// Values are JSON-encoded into UserDefaults, and optionally mirrored to
/// `NSUbiquitousKeyValueStore` so a second HomePad or the iPhone companion
/// picks them up.
///
/// Reads are decoded once and kept until the key is written, reset or changed
/// in iCloud. The kiosk reads about a dozen settings every second and view
/// bodies read them on every render, so decoding JSON each time added up on a
/// display that runs all day. Write settings through this store, not straight
/// to `UserDefaults`, or the kept value goes stale.
@MainActor
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    /// Decoded values by key name. A key whose stored data is missing or does
    /// not decode maps to `Missing`, so its default is returned without a lookup.
    @ObservationIgnored private var decoded: [String: Any] = [:]
    /// Keys iCloud no longer carries (`stopICloudSync(forKeyNamed:)`).
    @ObservationIgnored private var cloudExcluded: Set<String> = []
    /// Bumped on every write so SwiftUI views reading settings refresh.
    public private(set) var revision = 0

    public init(defaults: UserDefaults = .standard, useICloud: Bool = false) {
        self.defaults = defaults
        self.cloud = useICloud ? NSUbiquitousKeyValueStore.default : nil
        if let cloud {
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud, queue: .main
            ) { [weak self] note in
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                MainActor.assumeIsolated { self?.pullFromCloud(keys: keys) }
            }
            cloud.synchronize()
        }
    }

    public subscript<Value: Codable>(key: SettingKey<Value>) -> Value {
        get {
            _ = revision
            switch decoded[key.name] {
            case let value as Value:
                return value
            case is Missing:
                return key.defaultValue
            default:
                return decode(key)
            }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key.name)
            if key.syncsWithICloud { cloud?.set(data, forKey: key.name) }
            // Decoded again on the next read, so a read always returns what
            // the stored data decodes to, as it did before values were kept.
            decoded[key.name] = nil
            revision += 1
        }
    }

    public func reset<Value: Codable>(_ key: SettingKey<Value>) {
        defaults.removeObject(forKey: key.name)
        if key.syncsWithICloud { cloud?.removeObject(forKey: key.name) }
        decoded[key.name] = nil
        revision += 1
    }

    /// True when something is saved for the key, false when it reads its default.
    public func contains<Value: Codable>(_ key: SettingKey<Value>) -> Bool {
        _ = revision
        return defaults.object(forKey: key.name) != nil
    }

    /// The names of saved keys that start with `prefix`, for a module that
    /// keeps one key per person or per item under a common prefix.
    public func keyNames(withPrefix prefix: String) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Moves what is saved under one key name to another, as it is stored,
    /// replacing what the new name held. Nothing happens when the old name has
    /// nothing saved. A person whose ID changed keeps their settings this way.
    public func moveValue(fromKeyNamed old: String, toKeyNamed new: String) {
        guard old != new, let data = defaults.object(forKey: old) else { return }
        defaults.set(data, forKey: new)
        defaults.removeObject(forKey: old)
        decoded[old] = nil
        decoded[new] = nil
        revision += 1
    }

    /// Stops taking a key's value from iCloud. A key that moved to the
    /// household's own sharing between HomePads (Connect's peer link) calls
    /// this, so an older copy another device still writes to iCloud never
    /// overwrites what the household shares.
    public func stopICloudSync(forKeyNamed name: String) {
        cloudExcluded.insert(name)
    }

    private func decode<Value: Codable>(_ key: SettingKey<Value>) -> Value {
        guard let data = defaults.data(forKey: key.name),
              let value = try? Self.decoder.decode(Value.self, from: data) else {
            decoded[key.name] = Missing()
            return key.defaultValue
        }
        decoded[key.name] = value
        return value
    }

    private func pullFromCloud(keys: [String]) {
        guard let cloud else { return }
        for key in keys where !cloudExcluded.contains(key) {
            if let data = cloud.data(forKey: key) {
                defaults.set(data, forKey: key)
            }
            decoded[key] = nil
        }
        revision += 1
    }

    /// Marks a key with no usable stored value.
    private struct Missing {}

    private static let decoder = JSONDecoder()
}

#if canImport(SwiftUI)
import SwiftUI

public extension SettingsStore {
    /// A SwiftUI binding to a setting, for toggles and pickers in settings panes.
    func binding<Value: Codable>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(get: { self[key] }, set: { self[key] = $0 })
    }
}
#endif
