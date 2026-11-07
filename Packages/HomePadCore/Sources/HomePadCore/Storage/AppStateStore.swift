import Foundation
import Observation

/// What each app was showing when it was closed, so it reopens there: its
/// configuration (view mode, filter, tab) and its position (the date, the open
/// album, the pane). Views use the `@AppState` property wrapper. Code outside
/// views, such as a module's shared model, reads and writes keys here directly.
///
/// Persistent values go through `SettingsStore` and stay on this iPad. Session
/// values stay in memory for this launch. Member-scoped values are kept for the
/// recognized member, or under one shared "guest" owner while nobody is
/// recognized, so one person's state never shows for someone else.
///
/// Apps own what happens after a restore: a value that no longer exists or
/// that the person may not see (a deleted list, another person's device) falls
/// back to the app's default, and an explicit request (a launch argument, a
/// widget or the assistant naming what to show) is applied over it.
@MainActor
@Observable
public final class AppStateStore {
    /// How long a time position (`AppStateLifetime.timePosition`), such as
    /// Calendar's date, is restored after it was chosen, as long as it is still
    /// the same day. Long enough to come back from making lunch to the week
    /// you were planning, short enough that the next morning opens on today.
    public static let timePositionLifetime: TimeInterval = 4 * 60 * 60

    @ObservationIgnored private let settings: SettingsStore?
    @ObservationIgnored private let household: Household?
    /// Session values, and every value while `keepsStateInMemory`. Observed,
    /// so views reading a value redraw when it is written.
    private var memory: [String: Any] = [:]
    /// True after `startFresh()`: every value starts from its default and
    /// stays in memory, and nothing saved on the iPad is read or changed.
    public private(set) var keepsStateInMemory = false

    /// - Parameters:
    ///   - settings: Where persistent values go. Nil keeps everything in memory.
    ///   - household: Who is recognized, for member-scoped values. Nil treats
    ///     everyone as a guest.
    public init(settings: SettingsStore?, household: Household?) {
        self.settings = settings
        self.household = household
        household?.onMemberIDChange { [weak self] old, new in self?.moveMember(from: old, to: new) }
    }

    /// Moves a person's member-scoped values to their new ID, so apps reopen
    /// where they left them after this iPad joined a household that knew them
    /// by another ID.
    func moveMember(from old: UUID, to new: UUID) {
        let oldSuffix = "." + old.uuidString
        func renamed(_ name: String) -> String { String(name.dropLast(oldSuffix.count)) + "." + new.uuidString }
        if let settings {
            for name in settings.keyNames(withPrefix: "appState.") where name.hasSuffix(oldSuffix) {
                settings.moveValue(fromKeyNamed: name, toKeyNamed: renamed(name))
            }
        }
        for name in memory.keys where name.hasSuffix(oldSuffix) {
            memory[renamed(name)] = memory.removeValue(forKey: name)
        }
    }

    /// A store that keeps everything in memory, for previews and views shown
    /// outside HomePad's environment.
    public static func inMemory() -> AppStateStore {
        AppStateStore(settings: nil, household: nil)
    }

    // MARK: Reading and writing

    /// The saved value, or nil when nothing is saved for the current owner or
    /// it went stale (`AppStateLifetime.timePosition`).
    /// - Parameter openedAt: When the app opened. Staleness is judged against
    ///   it, so a value restored on opening stays while the app is open.
    public func savedValue<Value>(_ key: AppStateKey<Value>, openedAt: Date = Date()) -> Value? {
        guard let entry = entry(for: key) else { return nil }
        switch key.lifetime {
        case .always:
            return entry.value
        case .timePosition:
            return Self.isFresh(savedAt: entry.savedAt, openedAt: openedAt) ? entry.value : nil
        }
    }

    /// The saved value, or the key's default.
    public subscript<Value>(key: AppStateKey<Value>) -> Value {
        get { savedValue(key) ?? key.defaultValue }
        set { set(newValue, for: key) }
    }

    /// Saves a value for the current owner. Writing the value already saved
    /// does nothing while it is still restorable, so bindings that write on
    /// every redraw stay cheap and a time position keeps the time it was chosen.
    public func set<Value>(_ value: Value, for key: AppStateKey<Value>, now: Date = Date()) {
        if savedValue(key, openedAt: now) == value { return }
        let entry = AppStateEntry(value: value, savedAt: now)
        let name = storageName(for: key)
        if let settings, key.storage == .persistent, !keepsStateInMemory {
            settings[Self.settingKey(name, for: key)] = entry
        } else {
            memory[name] = entry
        }
    }

    /// Forgets the current owner's value, so the app opens on its default.
    public func reset<Value>(_ key: AppStateKey<Value>) {
        let name = storageName(for: key)
        if let settings, key.storage == .persistent, !keepsStateInMemory {
            settings.reset(Self.settingKey(name, for: key))
        } else {
            memory[name] = nil
        }
    }

    /// Starts every app from its defaults for the rest of this launch and
    /// keeps what they save in memory. Screenshot and UI test launches use it
    /// (any launch argument that opens a screen), so they begin alike and
    /// never change what the iPad saved.
    public func startFresh() {
        keepsStateInMemory = true
        memory = [:]
    }

    // MARK: Rules

    /// The staleness rule for time positions: restored on the same day, and
    /// within `timePositionLifetime` of being chosen.
    public static func isFresh(savedAt: Date, openedAt: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(savedAt, inSameDayAs: openedAt) && openedAt.timeIntervalSince(savedAt) < timePositionLifetime
    }

    /// Who a key's value belongs to right now: "household", a recognized
    /// member's identifier, or "guest".
    public func owner(for scope: AppStateScope) -> String {
        switch scope {
        case .household:
            return "household"
        case .member:
            guard let household, household.isPersonalContentUnlocked, let id = household.activeMemberID else { return "guest" }
            return id.uuidString
        }
    }

    /// The name a value is stored under: `appState.<key>.<owner>`.
    func storageName<Value>(for key: AppStateKey<Value>) -> String {
        "appState.\(key.name).\(owner(for: key.scope))"
    }

    // MARK: Storage

    private func entry<Value>(for key: AppStateKey<Value>) -> AppStateEntry<Value>? {
        let name = storageName(for: key)
        if let settings, key.storage == .persistent, !keepsStateInMemory {
            return settings[Self.settingKey(name, for: key)]
        }
        return memory[name] as? AppStateEntry<Value>
    }

    private static func settingKey<Value>(_ name: String, for key: AppStateKey<Value>) -> SettingKey<AppStateEntry<Value>?> {
        SettingKey(name, default: nil)
    }
}
