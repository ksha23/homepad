import Foundation
import HomePadCore

/// One widget on a face, as saved: which widget, its size, and the cell its
/// top leading corner sits in.
struct FaceWidgetPlacement: Codable, Hashable, Sendable, Identifiable {
    /// Tells two copies of one widget apart, and matches a widget between the two orientations.
    var id: UUID
    /// The widget's `WidgetDescriptor.id`.
    var widgetID: String
    var size: WidgetSize
    /// Nil until the widget is placed by hand in this orientation. The face
    /// then puts it with the others that have none, along the edge its fill
    /// names (`FaceGridFill`).
    var cell: FaceGridCell?

    init(id: UUID = UUID(), widgetID: String, size: WidgetSize, cell: FaceGridCell? = nil) {
        self.id = id
        self.widgetID = widgetID
        self.size = size
        self.cell = cell
    }

    private enum CodingKeys: String, CodingKey {
        case id, widgetID = "widget", size, cell
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        widgetID = try container.decode(String.self, forKey: .widgetID)
        // A size a later version added reads as small, the size every widget has room for.
        size = try WidgetSize(rawValue: container.decode(String.self, forKey: .size)) ?? .small
        cell = try container.decodeIfPresent(FaceGridCell.self, forKey: .cell)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(widgetID, forKey: .widgetID)
        try container.encode(size.rawValue, forKey: .size)
        try container.encodeIfPresent(cell, forKey: .cell)
    }
}

/// The widgets on a saved face, arranged for each orientation.
///
/// Each orientation keeps its own arrangement once someone edits it there.
/// Until then it shows the other orientation's widgets in reading order,
/// each in the first open area (`placements(for:)`). Both orientations hold
/// the same widgets: one added in either joins the other in its first open
/// area, and one removed in either leaves both (`save(_:for:)`).
///
/// Each widget's own settings (Edit Widget) are kept once, by its placement
/// ID, so it shows the same in both orientations, and they go with it.
///
/// A placement can be a widget stack (`WidgetStack`). Its widgets are kept
/// once too, by placement ID (`stacks`), and the placement itself names the
/// stack's first widget and that widget's settings, so a HomePad from before
/// stacks shows that widget in its place.
struct FaceWidgetLayout: Codable, Hashable, Sendable {
    /// The landscape arrangement. Nil until someone edits the face in landscape.
    var landscape: [FaceWidgetPlacement]?
    /// The portrait arrangement. Nil until someone edits the face in portrait.
    var portrait: [FaceWidgetPlacement]?
    /// Widgets' settings by placement ID (`uuidString`). Nil until a setting
    /// changes, so faces saved before settings read as they were.
    var widgetSettings: [String: WidgetSettings]?
    /// The widget stacks by placement ID (`uuidString`). Nil while the face
    /// has none, so faces saved before stacks read and save as they were.
    var stacks: [String: WidgetStack]?

    init(landscape: [FaceWidgetPlacement]? = nil, portrait: [FaceWidgetPlacement]? = nil,
         widgetSettings: [String: WidgetSettings]? = nil, stacks: [String: WidgetStack]? = nil) {
        self.landscape = landscape
        self.portrait = portrait
        self.widgetSettings = widgetSettings
        self.stacks = stacks
    }

    /// The stack at a placement, nil for a single widget.
    func stack(for id: UUID) -> WidgetStack? {
        stacks?[id.uuidString]
    }

    /// Changes the widgets at a placement, in both orientations. Two or more
    /// make it a stack, one left makes it that widget with its settings, and
    /// none takes it off the face.
    mutating func setStack(_ stack: WidgetStack, for id: UUID) {
        var all = stacks ?? [:]
        guard let first = stack.members.first else {
            all[id.uuidString] = nil
            stacks = all.isEmpty ? nil : all
            for orientation in FaceGrid.Orientation.allCases { self[orientation]?.removeAll { $0.id == id } }
            setSettings(WidgetSettings(), for: id)
            return
        }
        all[id.uuidString] = stack.members.count > 1 ? stack : nil
        stacks = all.isEmpty ? nil : all
        for orientation in FaceGrid.Orientation.allCases {
            guard let index = self[orientation]?.firstIndex(where: { $0.id == id }) else { continue }
            self[orientation]?[index].widgetID = first.widgetID
        }
        setSettings(first.settings ?? WidgetSettings(), for: id)
    }

    /// The widgets a placement stands for: its stack's, or its widget as a stack of one.
    func members(of placement: FaceWidgetPlacement) -> [WidgetStack.Member] {
        stack(for: placement.id)?.members
            ?? [WidgetStack.Member(id: placement.id.uuidString, widgetID: placement.widgetID, settings: settings(for: placement.id))]
    }

    /// A widget's own settings, empty when none changed.
    func settings(for id: UUID) -> WidgetSettings {
        widgetSettings?[id.uuidString] ?? WidgetSettings()
    }

    /// Saves a widget's settings for both orientations.
    mutating func setSettings(_ settings: WidgetSettings, for id: UUID) {
        var all = widgetSettings ?? [:]
        all[id.uuidString] = settings.isEmpty ? nil : settings
        widgetSettings = all.isEmpty ? nil : all
    }

    subscript(orientation: FaceGrid.Orientation) -> [FaceWidgetPlacement]? {
        get { orientation == .landscape ? landscape : portrait }
        set {
            if orientation == .landscape { landscape = newValue } else { portrait = newValue }
        }
    }

    /// True when the face has no widgets.
    var isEmpty: Bool {
        (landscape ?? []).isEmpty && (portrait ?? []).isEmpty
    }

    /// The placements to arrange in an orientation: its own once edited there.
    /// Otherwise the other orientation's widgets in reading order of their
    /// cells, with no cells of their own, so they reflow into this grid.
    func placements(for orientation: FaceGrid.Orientation) -> [FaceWidgetPlacement] {
        if let own = self[orientation] { return own }
        let other = self[orientation.other] ?? []
        return Self.readingOrder(other).map { placement in
            var reflowed = placement
            reflowed.cell = nil
            return reflowed
        }
    }

    /// Saves an arrangement made by hand in one orientation. A widget added
    /// there joins the other orientation's arrangement with no cell, so it
    /// takes the first open area there, and a widget removed there leaves it,
    /// with its settings.
    mutating func save(_ placements: [FaceWidgetPlacement], for orientation: FaceGrid.Orientation) {
        defer { dropSettingsOfRemovedWidgets() }
        self[orientation] = placements
        guard var other = self[orientation.other] else { return }
        let kept = Set(placements.map(\.id))
        other.removeAll { !kept.contains($0.id) }
        let known = Set(other.map(\.id))
        for placement in placements where !known.contains(placement.id) {
            var added = placement
            added.cell = nil
            other.append(added)
        }
        self[orientation.other] = other
    }

    /// Keeps settings and stacks only for widgets still on the face.
    private mutating func dropSettingsOfRemovedWidgets() {
        let ids = Set(((landscape ?? []) + (portrait ?? [])).map(\.id.uuidString))
        if let all = widgetSettings {
            let kept = all.filter { ids.contains($0.key) }
            widgetSettings = kept.isEmpty ? nil : kept
        }
        if let all = stacks {
            let kept = all.filter { ids.contains($0.key) }
            stacks = kept.isEmpty ? nil : kept
        }
    }

    /// Placements sorted the way a person reads the grid: top row first, then
    /// leading to trailing. Placements without a cell keep their order after them.
    static func readingOrder(_ placements: [FaceWidgetPlacement]) -> [FaceWidgetPlacement] {
        placements.enumerated().sorted { left, right in
            switch (left.element.cell, right.element.cell) {
            case let (a?, b?) where (a.row, a.column) != (b.row, b.column):
                return (a.row, a.column) < (b.row, b.column)
            case (.some, .none): return true
            case (.none, .some): return false
            default: return left.offset < right.offset
            }
        }
        .map(\.element)
    }
}
