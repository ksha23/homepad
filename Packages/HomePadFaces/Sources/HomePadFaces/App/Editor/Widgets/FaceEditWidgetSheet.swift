import HomePadCore
import HomePadUI
import SwiftUI

/// Which widget on the face being edited Edit Widget is open for.
struct FaceWidgetSettingsRequest: Identifiable, Equatable {
    /// The widget's placement ID, the same in both orientations.
    let id: UUID
}

/// Edit Widget for a widget on the face being edited (HomePadUI's
/// `EditWidgetSheet`). Its settings go in the face's widget layout, once for
/// both orientations (`FaceWidgetLayout.settings(for:)`), and the preview
/// behind the sheet shows each change at once. Like every other change in
/// the editor, they are kept when the editor's Done saves the face. The sheet
/// closes on its own when the widget is gone or a personal widget locks again.
/// For a stack it is Edit Stack (`FaceEditStackSheet`).
struct FaceEditWidgetSheet: View {
    let request: FaceWidgetSettingsRequest
    let definition: FaceDefinition
    @Binding var face: FaceConfiguration
    /// The face's widgets as saved, in the orientation being arranged.
    let board: FaceWidgetBoard

    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if face.widgetStack(for: request.id, legacySize: definition.widgets.legacySize) != nil {
            FaceEditStackSheet(request: request, definition: definition, face: $face, board: board)
        } else if let item = board.item(request.id), let widget = registry.widget(item.widgetID), widget.hasSettings,
           !FaceEditWidgetSheet.isLocked(widget, household: services.household) {
            EditWidgetSheet(widget: widget, size: item.size, tile: board.grid.tileSize(item.size), settings: settings)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private var settings: Binding<WidgetSettings> {
        let legacySize = definition.widgets.legacySize
        return Binding(
            get: { face.widgetSettings(for: request.id, legacySize: legacySize) },
            set: { face.setWidgetSettings($0, for: request.id, legacySize: legacySize) }
        )
    }

    /// Personal widgets keep their settings closed until someone is recognized, as their previews stay locked.
    static func isLocked(_ widget: WidgetDescriptor, household: Household) -> Bool {
        let showPersonal = household.isPersonalContentUnlocked || FaceDebugOptions.forcesPersonal
        return FaceWidgetAccess.of(widget, showPersonal: showPersonal, keepsPersonalPlaces: true) == .locked
    }
}

/// Edit Stack for a stack on the face being edited (HomePadUI's
/// `EditStackSheet`): its widgets to reorder, remove or edit, Smart Rotate,
/// and the widgets that can join it. The stack goes in the face's widget
/// layout, once for both orientations (`FaceWidgetLayout.stacks`), the
/// preview behind the sheet shows each change at once, and the editor's Done
/// keeps them with the face. Once one widget is left the stack becomes that
/// widget, and the sheet closes.
struct FaceEditStackSheet: View {
    let request: FaceWidgetSettingsRequest
    let definition: FaceDefinition
    @Binding var face: FaceConfiguration
    /// The face's widgets as saved, in the orientation being arranged.
    let board: FaceWidgetBoard

    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let item = board.item(request.id), face.widgetStack(for: request.id, legacySize: legacySize) != nil {
            EditStackSheet(
                stack: stack, size: item.size, tile: board.grid.tileSize(item.size), widget: { registry.widget($0) },
                addable: registry.widgets, isLocked: { FaceEditWidgetSheet.isLocked($0, household: services.household) }
            ) { widget, settings in
                FaceWidgetTile(widget: widget, size: item.size, settings: settings)
            }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private var legacySize: WidgetSize { definition.widgets.legacySize }

    private var stack: Binding<WidgetStack> {
        Binding(
            get: { face.widgetStack(for: request.id, legacySize: legacySize) ?? WidgetStack(members: []) },
            set: { changed in
                withAnimation(Theme.Motion.settle) { face.setWidgetStack(changed, for: request.id, legacySize: legacySize) }
            }
        )
    }
}
