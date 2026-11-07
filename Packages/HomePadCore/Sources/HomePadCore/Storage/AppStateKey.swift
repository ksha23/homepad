import Foundation

/// Whose saved state a value is.
public enum AppStateScope: Sendable {
    /// One value for the whole household, guests included. Household apps:
    /// Home, Timers, Settings, Faces.
    case household
    /// One value for each recognized member, and one that everyone else shares
    /// while nobody is recognized (picked by hand counts as not recognized).
    /// Personal apps: Calendar, Reminders, Photos, Find My, Assistant.
    /// A person's open list or album never shows for someone else.
    case member
}

/// Where a saved value lives.
public enum AppStateStorage: Sendable {
    /// `SettingsStore`, so UserDefaults on this iPad. Survives relaunch. Never
    /// synced to iCloud: what one iPad was showing means nothing on another.
    case persistent
    /// Memory, for this launch only. For values that change often and lose
    /// their meaning after a relaunch, such as a scroll position or a map region.
    case session
}

/// How long a saved value is worth restoring.
public enum AppStateLifetime: Sendable {
    /// However long ago it was saved: configuration (view mode, sort, tab) and
    /// positions that are places rather than times (an album, a room, a pane).
    case always
    /// A position in time, such as the date Calendar shows. Restored only on
    /// the day it was saved and within `AppStateStore.timePositionLifetime`.
    /// After that the app opens on its default, today, and keeps its configuration.
    case timePosition
}

/// One piece of state an app keeps between openings, like `SettingKey` for a
/// setting. Name it `<app>.<state>`, for example `calendar.mode`. Never rename
/// a key or change its stored format, or saved state stops loading.
///
///     static let mode = AppStateKey("calendar.mode", default: CalendarDisplayMode.day, scope: .member)
///     static let date = AppStateKey("calendar.date", default: Date(), scope: .member, lifetime: .timePosition)
public struct AppStateKey<Value: Codable & Equatable & Sendable>: Sendable {
    public let name: String
    public let scope: AppStateScope
    public let storage: AppStateStorage
    public let lifetime: AppStateLifetime
    private let makeDefault: @Sendable () -> Value

    /// - Parameter defaultValue: What the app shows when nothing is saved, the
    ///   saved value is stale, or it no longer exists. Evaluated when needed, so
    ///   `Date()` means the day the app opens.
    public init(
        _ name: String, default defaultValue: @autoclosure @escaping @Sendable () -> Value,
        scope: AppStateScope = .household, storage: AppStateStorage = .persistent, lifetime: AppStateLifetime = .always
    ) {
        self.name = name
        self.makeDefault = defaultValue
        self.scope = scope
        self.storage = storage
        self.lifetime = lifetime
    }

    /// A fresh default.
    public var defaultValue: Value { makeDefault() }
}

/// A saved value and when it was saved, as stored.
struct AppStateEntry<Value: Codable & Sendable>: Codable, Sendable {
    var value: Value
    var savedAt: Date
}
