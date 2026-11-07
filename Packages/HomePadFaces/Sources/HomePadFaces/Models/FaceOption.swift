import SwiftUI

/// One curated choice inside an option, such as the "Heavy" style.
struct FaceChoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String?

    init(_ id: String, _ title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// A complication slot, such as a city, an accessory or a camera, that the
/// editor lets you fill by tapping it. Widgets go on the face's grid instead
/// (`FaceWidgetLayout`).
struct FaceSlot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// What an empty slot means when the face fills it itself, such as
    /// "Automatic" or "Current Location". Nil when an empty slot shows nothing.
    var automaticTitle: String?
}

/// Where a slot's items come from.
enum SlotGallery: Sendable {
    /// A fixed list of world cities.
    case cities
    /// The home's accessories, by room, and its scenes (`services.smartHome`).
    case accessoriesAndScenes
    /// The home's cameras (`services.smartHome`).
    case cameras

    /// What an empty slot offers in the editor.
    var addTitle: String {
        switch self {
        case .cities: "Add City"
        case .accessoriesAndScenes: "Add Accessory"
        case .cameras: "Add Camera"
        }
    }
}

/// One page of the face editor, like "Style", "Color" or "Complications"
/// on Apple Watch. Each face declares a small fixed set of these.
struct FaceOption: Identifiable {
    enum Kind {
        /// Swipe through a few named variants.
        case choices([FaceChoice])
        /// A background from a subset of the fixed list (stored under the
        /// option's ID), and the other parts the face lets people color, each
        /// under its own key (`FaceColorChoice`).
        case colors([FaceColor], roles: FaceColorRoles)
        /// Tap a slot, then pick from a gallery.
        case slots([FaceSlot], SlotGallery)
        /// A page the face draws itself (photo source, rotation rules).
        case custom(@MainActor (Binding<FaceConfiguration>) -> AnyView)
        /// The face's widgets, arranged on its grid by dragging them on the
        /// preview (`FaceWidgetLayout`). Every face that takes widgets has this page.
        case widgetGrid
    }

    /// How the editor draws the cards of a `.choices` option.
    enum CardStyle: Sendable {
        /// A small picture of the face with the choice applied, for choices that change the look.
        case faceThumbnail
        /// The choice's symbol, for choices a still picture cannot show (motion, timing).
        case symbol
    }

    let id: String
    let title: String
    let kind: Kind
    let defaultValue: String
    /// The distance the editor previews this page at, for an option that only
    /// shows at one distance. Nil keeps the
    /// distance the person picked.
    let previewDistance: EditorDistance?
    /// How the editor draws this option's choices.
    let cardStyle: CardStyle
    /// One sentence the editor shows under the page's controls, such as what
    /// leaving every slot empty does.
    let note: String?
    /// Whether the option applies to a configuration. An option that does not
    /// (how often photos change, for a face showing one photo) has no editor
    /// page and no place in the face's caption.
    let isShown: @MainActor (FaceConfiguration) -> Bool

    init(id: String, title: String, kind: Kind, defaultValue: String = "",
         previewDistance: EditorDistance? = nil, cardStyle: CardStyle = .faceThumbnail, note: String? = nil,
         isShown: @escaping @MainActor (FaceConfiguration) -> Bool = { _ in true }) {
        self.id = id
        self.title = title
        self.kind = kind
        self.defaultValue = defaultValue
        self.previewDistance = previewDistance
        self.cardStyle = cardStyle
        self.note = note
        self.isShown = isShown
    }

    /// A style option. The first choice is the default unless one is named.
    /// - Parameter cardStyle: `.symbol` when the styles differ only in motion.
    static func style(_ choices: [FaceChoice], default value: String? = nil, cardStyle: CardStyle = .faceThumbnail) -> FaceOption {
        FaceOption(id: "style", title: "Style", kind: .choices(choices), defaultValue: value ?? choices.first?.id ?? "",
                   cardStyle: cardStyle)
    }

    /// A color option: a background limited to some entries of the fixed list,
    /// plus the text and accent colors when the face has `roles` for them.
    static func color(_ colors: [FaceColor] = FaceColor.allCases, default value: FaceColor,
                      roles: FaceColorRoles = .all) -> FaceOption {
        FaceOption(id: "color", title: "Color", kind: .colors(colors, roles: roles), defaultValue: value.rawValue)
    }

    /// True when a stored value is still one of this option's choices.
    func accepts(_ value: String) -> Bool {
        switch kind {
        case .choices(let choices): choices.contains { $0.id == value }
        case .colors(let colors, _): colors.contains { $0.rawValue == value }
        case .slots, .custom, .widgetGrid: true
        }
    }

    /// The widgets page every face that takes widgets shows last
    /// (`FaceDefinition.options(for:)`). Widgets show at every distance, so it
    /// keeps the distance the person picked.
    static let widgetGrid = FaceOption(id: "widgets", title: "Widgets", kind: .widgetGrid)

    /// True for the widgets page.
    var isWidgetGrid: Bool {
        if case .widgetGrid = kind { return true }
        return false
    }

    /// The parts a `.colors` option colors besides the background, otherwise none.
    var colorRoles: FaceColorRoles {
        if case .colors(_, let roles) = kind { return roles }
        return []
    }

    /// The choices of a `.choices` option, otherwise empty.
    var choices: [FaceChoice] {
        if case .choices(let choices) = kind { return choices }
        return []
    }
}
