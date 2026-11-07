import Foundation
import HomePadCore

/// One saved face, like a face in the Watch app's "My Faces": a face kind
/// plus the choices made in the editor. Values are keyed by `FaceOption.id`.
struct FaceConfiguration: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// The face kind, for example `faces.numerals`.
    var faceID: String
    /// Single choices such as style and color, keyed by option ID.
    var values: [String: String]
    /// Complication slots (cities, accessories, cameras): slot ID to the
    /// chosen item ID. Faces saved before the widget grid kept their widgets
    /// here too (`FaceWidgetMigration`).
    var slots: [String: String]
    /// Multi-value choices, such as hand-picked photo identifiers.
    var items: [String: [String]]
    /// The widgets on the face's grid, for each orientation. Nil for a face
    /// saved before the grid, whose widgets are still in its slots
    /// (`widgets(legacySize:)` reads them).
    var widgetLayout: FaceWidgetLayout?
    /// The mini widget in the face's top left corner, mirroring the profile
    /// button in the top right (`FaceMiniWidgetLayer`). Nil, the default and
    /// what faces saved before mini widgets read, leaves the corner empty.
    var miniWidget: MiniWidgetPlacement?

    init(id: UUID = UUID(), faceID: String, values: [String: String] = [:],
         slots: [String: String] = [:], items: [String: [String]] = [:], widgetLayout: FaceWidgetLayout? = nil,
         miniWidget: MiniWidgetPlacement? = nil) {
        self.id = id
        self.faceID = faceID
        self.values = values
        self.slots = slots
        self.items = items
        self.widgetLayout = widgetLayout
        self.miniWidget = miniWidget
    }

    /// The stored value for an option, or the option's default when the stored
    /// value is missing or no longer one of the option's choices.
    func value(_ option: FaceOption) -> String {
        guard let stored = values[option.id], option.accepts(stored) else { return option.defaultValue }
        return stored
    }

    /// The background chosen for a color option.
    func color(_ option: FaceOption) -> FaceColor {
        FaceColor(rawValue: value(option)) ?? .graphite
    }

    /// Everything chosen on a color option's page: the background, and the
    /// text and accent when the option offers them. A missing or unknown text
    /// or accent is automatic, so faces saved before these existed look as they did.
    func colors(_ option: FaceOption) -> FaceColorChoice {
        let roles = option.colorRoles
        return FaceColorChoice(
            background: color(option),
            text: roles.contains(.text) ? values[FaceColorChoice.textKey].flatMap(FaceTextColor.init(rawValue:)) : nil,
            accent: roles.contains(.accent) ? values[FaceColorChoice.accentKey].flatMap(FaceAccent.init(id:)) : nil
        )
    }

    /// The item in a slot, if any.
    func slot(_ id: String) -> String? {
        guard let value = slots[id], !value.isEmpty else { return nil }
        return value
    }

    /// A configuration that is not saved anywhere, used when nobody saved one of this kind.
    static func unsaved(_ faceID: String) -> FaceConfiguration {
        FaceConfiguration(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(), faceID: faceID)
    }
}
