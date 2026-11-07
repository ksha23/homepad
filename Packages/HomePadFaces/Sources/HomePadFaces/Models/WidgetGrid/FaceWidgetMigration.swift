import Foundation
import HomePadCore

/// Faces saved before the widget grid kept their widgets in slots named
/// "widget1", "widget2" and so on: four on Modular, three on Photos. They
/// become grid placements in slot order, each at the face's old widget size
/// (`FaceWidgetSupport.legacySize`) and with no cell, so each takes the first
/// open area in the face's fill order, where the face used to draw them.
/// Nobody's choice is lost: a widget the face cannot fit stays saved
/// (`FaceWidgetBoard.leftOut`).
enum FaceWidgetMigration {
    /// The old slots' IDs start with this, followed by the slot number.
    static let slotPrefix = "widget"

    /// The widget IDs in a configuration's old slots, in slot number order. Empty slots are skipped.
    static func legacyWidgetIDs(in configuration: FaceConfiguration) -> [String] {
        configuration.slots
            .compactMap { key, value -> (number: Int, id: String)? in
                guard key.hasPrefix(slotPrefix), let number = Int(key.dropFirst(slotPrefix.count)),
                      !value.isEmpty else { return nil }
                return (number, value)
            }
            .sorted { $0.number < $1.number }
            .map(\.id)
    }

    /// The layout for a configuration's old slots: their widgets in landscape,
    /// unplaced, so portrait reflows from it. Nil when the slots are empty.
    static func layout(for configuration: FaceConfiguration, size: WidgetSize) -> FaceWidgetLayout? {
        let ids = legacyWidgetIDs(in: configuration)
        guard !ids.isEmpty else { return nil }
        let placements = ids.enumerated().map { index, widgetID in
            FaceWidgetPlacement(id: placementID(face: configuration.id, slot: index), widgetID: widgetID, size: size)
        }
        return FaceWidgetLayout(landscape: placements)
    }

    /// The same ID for a slot's widget every time the face is read, so a face
    /// that has not been edited since keeps its widgets' identity between redraws.
    static func placementID(face: UUID, slot: Int) -> UUID {
        var bytes = face.uuid
        bytes.14 = 0x57 // "W"
        bytes.15 = UInt8(truncatingIfNeeded: slot)
        return UUID(uuid: bytes)
    }
}

extension FaceConfiguration {
    /// The face's widgets: the saved layout, or for a face saved before the
    /// grid, the widgets in its old slots at `legacySize`.
    func widgets(legacySize: WidgetSize) -> FaceWidgetLayout {
        widgetLayout ?? FaceWidgetMigration.layout(for: self, size: legacySize) ?? FaceWidgetLayout()
    }

    /// Saves a board arranged in the editor as the face's layout for the
    /// board's orientation (`FaceWidgetLayout.save(_:for:)`), so widgets
    /// added or removed there join or leave the other orientation too.
    mutating func saveWidgets(_ board: FaceWidgetBoard, legacySize: WidgetSize) {
        adoptWidgetGrid(legacySize: legacySize)
        var layout = widgetLayout ?? FaceWidgetLayout()
        layout.save(board.placements, for: board.grid.orientation)
        widgetLayout = layout
    }

    /// The stack at a placement, nil for a single widget.
    func widgetStack(for id: UUID, legacySize: WidgetSize) -> WidgetStack? {
        widgets(legacySize: legacySize).stack(for: id)
    }

    /// Changes the widgets at a placement (`FaceWidgetLayout.setStack(_:for:)`):
    /// a stack while it holds two or more, that widget for one, off the face for none.
    mutating func setWidgetStack(_ stack: WidgetStack, for id: UUID, legacySize: WidgetSize) {
        adoptWidgetGrid(legacySize: legacySize)
        var layout = widgetLayout ?? FaceWidgetLayout()
        layout.setStack(stack, for: id)
        widgetLayout = layout
    }

    /// A widget's own settings (Edit Widget), empty when none changed.
    func widgetSettings(for id: UUID, legacySize: WidgetSize) -> WidgetSettings {
        widgets(legacySize: legacySize).settings(for: id)
    }

    /// Saves a widget's settings in the face's layout, for both orientations.
    mutating func setWidgetSettings(_ settings: WidgetSettings, for id: UUID, legacySize: WidgetSize) {
        adoptWidgetGrid(legacySize: legacySize)
        var layout = widgetLayout ?? FaceWidgetLayout()
        layout.setSettings(settings, for: id)
        widgetLayout = layout
    }

    /// Moves the widgets in the old slots into the layout and empties those
    /// slots, so the grid is the one place the face's widgets live. Nothing
    /// changes for a face that has a layout already.
    mutating func adoptWidgetGrid(legacySize: WidgetSize) {
        guard widgetLayout == nil else { return }
        widgetLayout = FaceWidgetMigration.layout(for: self, size: legacySize)
        for key in slots.keys where key.hasPrefix(FaceWidgetMigration.slotPrefix)
            && Int(key.dropFirst(FaceWidgetMigration.slotPrefix.count)) != nil {
            slots.removeValue(forKey: key)
        }
    }
}
