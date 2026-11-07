import HomePadCore
import HomePadUI
import SwiftUI

/// The widget or stack on the Home Screen that Edit Widget or Edit Stack is open for.
struct HomeWidgetEditRequest: Identifiable, Equatable {
    /// The widget's or stack's `HomeScreenItem` ID.
    let id: String
    /// The size the widget is drawn at on the Home Screen, for the preview.
    let tile: CGSize
}

/// What a launch argument opens once the Home Screen is drawn, for
/// screenshots: Edit Stack for the first stack (`-HomePadEditStack`), or Edit
/// Widget for the first copy of a widget (`-HomePadEditWidget <widgetID>`).
enum HomeFirstEdit: Equatable {
    case stack
    case widget(String)

    func matches(_ item: HomeScreenItem) -> Bool {
        switch self {
        case .stack: item.isStack
        case .widget(let widgetID): !item.isStack && item.targetID == widgetID
        }
    }
}

/// Edit Widget for a widget on the Home Screen (HomePadUI's `EditWidgetSheet`),
/// or Edit Stack for a stack (`HomeEditStackSheet`). A widget's settings live
/// with its place in the member's layout (`HomeScreenItem.settings`), so they
/// move with it and go when it is removed, and every change is saved as it
/// is made. The sheet closes on its own when the widget is no longer there
/// to change: removed, its module gone, or a personal widget whose owner is
/// no longer recognized. Same on All HomePads on the page changes the same
/// settings, so its choice moves with the widget too, into a stack and out.
struct HomeEditWidgetSheet: View {
    let request: HomeWidgetEditRequest
    let memberID: HouseholdMember.ID?
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(HomeScreenLayoutStore.self) private var layouts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if layouts.layout(for: memberID).stack(for: request.id) != nil {
            HomeEditStackSheet(request: request, memberID: memberID)
        } else if let editable {
            EditWidgetSheet(widget: editable.widget, size: editable.size, tile: request.tile, settings: settings)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    /// The widget and its size, while it is on the Home Screen, has settings and shows unlocked.
    private var editable: (widget: WidgetDescriptor, size: WidgetSize)? {
        guard let item = layouts.layout(for: memberID).allItems.first(where: { $0.id == request.id }),
              let tile = HomeScreenPages.resolve(item, registry: registry, access: PersonalAccess(household)),
              !tile.isLocked, case .widget(let widget, let size) = tile.content, widget.hasSettings else { return nil }
        return (widget, size)
    }

    private var settings: Binding<WidgetSettings> {
        Binding(
            get: { layouts.layout(for: memberID).settings(for: request.id) },
            set: { changed in layouts.update(for: memberID) { $0.setSettings(changed, for: request.id) } }
        )
    }
}

/// Edit Stack for a stack on the Home Screen (HomePadUI's `EditStackSheet`):
/// its widgets to reorder, remove or edit, Smart Rotate, and the widgets that
/// can join it. The stack lives with its place in the member's layout
/// (`HomeScreenItem.stack`), and each change is saved as it is made. Once one
/// widget is left the stack becomes that widget, and the sheet closes, as it
/// does when the stack is removed.
struct HomeEditStackSheet: View {
    let request: HomeWidgetEditRequest
    let memberID: HouseholdMember.ID?
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(HomeScreenLayoutStore.self) private var layouts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layout = layouts.layout(for: memberID)
        if let item = layout.allItems.first(where: { $0.id == request.id }), item.stack != nil {
            let access = PersonalAccess(household)
            EditStackSheet(
                stack: stack, size: item.widgetSize, tile: request.tile, widget: { registry.widget($0) },
                addable: registry.widgets.filter { access.visibility(isPersonal: $0.isPersonal) != .hidden },
                isLocked: { access.visibility(isPersonal: $0.isPersonal) != .visible }
            ) { widget, settings in
                widget.makeView(item.widgetSize).environment(\.widgetSettings, settings)
            }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private var stack: Binding<WidgetStack> {
        Binding(
            get: { layouts.layout(for: memberID).stack(for: request.id) ?? WidgetStack(members: []) },
            set: { changed in
                withAnimation(Theme.Motion.settle) {
                    layouts.update(for: memberID) { $0.setStack(changed, for: request.id) }
                }
            }
        )
    }
}
