import Foundation
import SwiftUI

/// One setting of a placed widget, like `SettingKey` for a module's settings.
/// Settings belong to the widget where it sits, and no other widget reads
/// them, so name the key after the setting alone, such as `list`. Never
/// rename a key or change its stored format, or saved widgets lose it. Names
/// that start with `homepad.` are HomePad's own, such as the mark Same on All
/// HomePads leaves (`WidgetSettingsOnEachHomePad.swift`).
///
///     static let list = WidgetSettingKey<String?>("list", default: nil)
public struct WidgetSettingKey<Value: Codable & Equatable & Sendable>: Sendable {
    public let name: String
    /// What the widget shows when nobody changed the setting: what it showed
    /// before it had settings.
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// The settings of one placed widget, as its Edit Widget page sets them. Each
/// widget on a Home Screen or a face keeps its own, so two Reminders widgets
/// can follow two lists. A widget reads them from `\.widgetSettings` and
/// declares the page with `WidgetDescriptor(…, settings:)`.
///
/// They start empty, and a key nobody set reads its default, so a widget
/// placed before it had settings looks as it did.
public struct WidgetSettings: Codable, Hashable, Sendable {
    private var values: [String: JSONValue]

    public init() {
        values = [:]
    }

    /// The setting's value, or its default when nobody set it or the stored
    /// value no longer decodes. Setting the default removes the key.
    public subscript<Value>(key: WidgetSettingKey<Value>) -> Value {
        get {
            guard let stored = values[key.name],
                  let data = try? JSONEncoder().encode(stored),
                  let value = try? JSONDecoder().decode(Value.self, from: data) else { return key.defaultValue }
            return value
        }
        set {
            guard newValue != key.defaultValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let stored = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                values[key.name] = nil
                return
            }
            values[key.name] = stored
        }
    }

    /// True when every setting reads its default.
    public var isEmpty: Bool { values.isEmpty }

    /// Stored as a plain object of setting names and values.
    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

public extension EnvironmentValues {
    /// The settings of the placed widget being drawn. The Home Screen and the
    /// faces set it for each widget. The widget gallery leaves it empty, so
    /// its previews show the defaults.
    @Entry var widgetSettings = WidgetSettings()
}
