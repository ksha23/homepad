import Foundation

// Same on All HomePads, the switch on a widget's Edit Widget page while
// HomePads share the household's setup.
//
// On, as every widget starts, the widget's settings are part of the shared
// Home Screen or face like the rest of it. Off, each HomePad keeps its own
// settings for the widget, such as Home Favorites with the kitchen's lights in
// the kitchen and the bedroom's in the bedroom. The widget itself, where it
// sits and its size, is still shared, and so is the switch.
//
// Off, the settings carry a mark (`EachHomePadMark`) with an ID that is the
// same on every HomePad:
//
// - On each iPad the settings are that iPad's own, so every place that draws
//   or edits the widget works as before. The mark keeps beside them the copy
//   the shared document carries.
// - The shared document carries that copy and the mark's ID. The copy is the
//   settings the widget had when the switch was turned off, which every
//   HomePad showed then, and an older HomePad that knows nothing of the switch
//   keeps showing it.
// - A module's `SharedDocumentDescriptor` turns one into the other: `read`
//   with `sharingWidgetSettings()`, and `apply` with
//   `keepingOwnWidgetSettings(from:)`, which finds this iPad's own settings by
//   the mark's ID wherever the widget sits now, in a stack or out of one.
//
// Turning the switch back on drops the mark, so this iPad's settings become
// the shared ones and reach the other HomePads like any other change.

/// What a widget's settings carry while each HomePad keeps its own.
struct EachHomePadMark: Codable, Hashable, Sendable {
    /// The same on every HomePad, so each finds its own settings for the
    /// widget in a layout another HomePad sent.
    var id: String
    /// On this iPad only: the settings the shared document carries for the
    /// widget. Never in the shared document itself.
    var shared: WidgetSettings?
}

public extension WidgetSettings {
    /// True unless Same on All HomePads was turned off for this widget.
    var isSameOnAllHomePads: Bool {
        self[Self.eachHomePad] == nil
    }

    /// Turns Same on All HomePads on or off. Off keeps these settings, now as
    /// this iPad's own and as the copy every HomePad shares. On drops the
    /// mark, so these settings become the shared ones.
    mutating func setSameOnAllHomePads(_ isOn: Bool) {
        guard isOn != isSameOnAllHomePads else { return }
        if isOn {
            self[Self.eachHomePad] = nil
        } else {
            self[Self.eachHomePad] = EachHomePadMark(id: UUID().uuidString, shared: self)
        }
    }
}

extension WidgetSettings {
    /// HomePad's own key. Widgets name theirs after a setting alone, such as
    /// `list`, so it never meets one of theirs.
    static let eachHomePad = WidgetSettingKey<EachHomePadMark?>("homepad.eachHomePad", default: nil)

    /// The settings the widget reads, without the mark.
    var withoutMark: WidgetSettings {
        var settings = self
        settings[Self.eachHomePad] = nil
        return settings
    }

    /// The settings as the shared document carries them: for a widget each
    /// HomePad keeps its own settings for, the shared copy and the mark's ID.
    var forSharing: WidgetSettings {
        guard let mark = self[Self.eachHomePad] else { return self }
        var settings = mark.shared ?? withoutMark
        settings[Self.eachHomePad] = EachHomePadMark(id: mark.id)
        return settings
    }

    /// Settings from another HomePad as this iPad keeps them: for a widget
    /// each HomePad keeps its own settings for, this iPad's own from `own`
    /// by the mark's ID, or these when it has none yet, with these as the
    /// shared copy.
    func keepingOwn(_ own: [String: WidgetSettings]) -> WidgetSettings {
        guard let mark = self[Self.eachHomePad] else { return self }
        var settings = own[mark.id]?.withoutMark ?? withoutMark
        settings[Self.eachHomePad] = EachHomePadMark(id: mark.id, shared: withoutMark)
        return settings
    }
}

public extension JSONValue {
    /// A shared document's content as the household shares it: each widget
    /// that keeps its own settings on each HomePad carries the shared copy
    /// instead of this iPad's. Everything else is as it was.
    func sharingWidgetSettings() -> JSONValue {
        mappingMarkedSettings { $0.forSharing }
    }

    /// A shared document's content from another HomePad as this iPad keeps
    /// it: each widget that keeps its own settings on each HomePad keeps this
    /// iPad's, found in `local`, the same document as this iPad has it now.
    func keepingOwnWidgetSettings(from local: JSONValue?) -> JSONValue {
        var own: [String: WidgetSettings] = [:]
        for settings in local?.markedSettings ?? [] {
            guard let id = settings[WidgetSettings.eachHomePad]?.id else { continue }
            own[id] = settings
        }
        return mappingMarkedSettings { $0.keepingOwn(own) }
    }
}

private extension JSONValue {
    /// This value as a widget's settings, when it is one that carries the mark.
    var asMarkedSettings: WidgetSettings? {
        guard self[WidgetSettings.eachHomePad.name] != nil else { return nil }
        return try? decoded(as: WidgetSettings.self)
    }

    /// Every widget's settings in the tree that carry the mark.
    var markedSettings: [WidgetSettings] {
        if let settings = asMarkedSettings { return [settings] }
        switch self {
        case .object(let fields):
            return fields.values.flatMap(\.markedSettings)
        case .array(let items):
            return items.flatMap(\.markedSettings)
        default:
            return []
        }
    }

    /// The tree with every widget's settings that carry the mark changed.
    func mappingMarkedSettings(_ change: (WidgetSettings) -> WidgetSettings) -> JSONValue {
        if let settings = asMarkedSettings, let changed = try? JSONValue(encoding: change(settings)) {
            return changed
        }
        switch self {
        case .object(let fields):
            return .object(fields.mapValues { $0.mappingMarkedSettings(change) })
        case .array(let items):
            return .array(items.map { $0.mappingMarkedSettings(change) })
        default:
            return self
        }
    }
}
