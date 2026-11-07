import SwiftUI

/// Reads and writes like `@State`, but the value is saved, so the app reopens
/// where it was left: in Calendar, the week view on the week someone moved to.
///
///     @AppState("calendar.mode", default: CalendarDisplayMode.day, scope: .member) private var mode
///     @AppState(CalendarState.date) private var selectedDate
///
///     HeaderPicker("View", selection: $mode, ...)
///
/// The value comes from `AppStateStore` in the environment, for whoever is
/// at the screen now (see `AppStateScope`), so it changes when they do. A time
/// position is judged stale against the moment the view appeared, so it never
/// jumps to today while the app is open. Defaults are made once per opening,
/// so `Date()` stays the same instant until the app closes.
///
/// Check a restored value before using it: a list, album, device or contact
/// that is gone or not visible to this person falls back to the app's default,
/// without writing over what was saved. Apply explicit requests (launch
/// arguments, a widget or the assistant naming what to show) by assigning them
/// when the view appears. They win, and the app then reopens on them too.
@MainActor
@propertyWrapper
public struct AppState<Value: Codable & Equatable & Sendable>: DynamicProperty {
    @Environment(AppStateStore.self) private var environmentStore: AppStateStore?
    @State private var visit = AppStateVisit()
    private let key: AppStateKey<Value>

    public init(_ key: AppStateKey<Value>) {
        self.key = key
    }

    /// A key declared in place. See `AppStateKey` for the parameters.
    public init(
        _ name: String, default defaultValue: @autoclosure @escaping @Sendable () -> Value,
        scope: AppStateScope = .household, storage: AppStateStorage = .persistent, lifetime: AppStateLifetime = .always
    ) {
        self.key = AppStateKey(name, default: defaultValue(), scope: scope, storage: storage, lifetime: lifetime)
    }

    public var wrappedValue: Value {
        get { store.savedValue(key, openedAt: visit.openedAt) ?? visit.defaultValue(for: key) }
        nonmutating set {
            guard newValue != wrappedValue else { return }
            store.set(newValue, for: key)
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }

    private var store: AppStateStore { environmentStore ?? visit.fallbackStore }
}

/// One opening of a view that uses `@AppState`: when it appeared, the default
/// it handed out, and a store for previews outside HomePad's environment.
/// A class, so reading it while drawing never changes view state.
@MainActor
final class AppStateVisit {
    let openedAt = Date()
    /// Boxed, so a default of nil is kept apart from no default yet.
    private var cachedDefault: [Any] = []
    private(set) lazy var fallbackStore = AppStateStore.inMemory()

    func defaultValue<Value>(for key: AppStateKey<Value>) -> Value {
        if !cachedDefault.isEmpty, let value = cachedDefault[0] as? Value { return value }
        let value = key.defaultValue
        cachedDefault = [value]
        return value
    }
}
