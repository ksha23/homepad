import HomePadCore
import HomePadUI
import SwiftUI

/// The controls under the preview on the widgets page: Add Widget, which
/// opens the widget gallery, Edit Widget for the selected widget when it has
/// settings or Edit Stack for a selected stack, the mini widget in the face's
/// top left corner (`TopLeftPicker`), and a line on what to do next. The
/// widgets themselves are arranged on the preview (`WidgetEditCanvas`).
struct WidgetsPage: View {
    /// The face's widgets as saved, in the orientation being arranged.
    let board: FaceWidgetBoard
    /// The face's mini widget, in its top left corner.
    @Binding var miniWidget: MiniWidgetPlacement?
    /// The selected widget, when it has settings.
    var selectedWithSettings: WidgetDescriptor?
    /// True when the selected widget is a stack, which Edit Stack changes.
    var selectsStack = false
    /// True while the selected widget is personal and nobody is recognized,
    /// so its settings stay closed like its content.
    var isSelectionLocked = false
    let onAdd: () -> Void
    var onEditWidget: () -> Void = {}

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            GlassCapsuleButton("Add Widget", systemImage: "plus", size: .regular, action: onAdd)
                .disabled(!board.hasRoom(for: .small))
            TopLeftPicker(placement: $miniWidget)
            if selectsStack {
                GlassCapsuleButton("Edit Stack", systemImage: "square.stack.3d.up", size: .regular, action: onEditWidget)
                    .accessibilityHint("Reorders, removes or edits the widgets in the stack")
                    .transition(.opacity)
            } else if let widget = selectedWithSettings {
                GlassCapsuleButton("Edit Widget", systemImage: "slider.horizontal.3", size: .regular, action: onEditWidget)
                    .disabled(isSelectionLocked)
                    .accessibilityHint("Changes what \(widget.title) shows")
                    .transition(.opacity)
            }
            Text(Self.note(for: board))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What to do next: add a first widget, arrange the ones there are, or make room.
    static func note(for board: FaceWidgetBoard) -> String {
        if board.items.isEmpty {
            return "Add a widget, then drag it where you want it. Widgets show at every distance."
        }
        if !board.hasRoom(for: .small) {
            return "This face is full. Remove a widget to add another."
        }
        return "Drag a widget to move it. Tap one, then drag its corner to change its size."
    }
}

/// The choice of the face's mini widget, in its top left corner: None or one
/// of the mini widgets. A menu that shows what is chosen, like a header picker
/// ("Top Left: Glance"). On a face it is always the smallest size, which fits
/// the face's top margin, so the face never moves for it. A bigger glance is
/// the Glance widget in the face's widget area.
struct TopLeftPicker: View {
    @Binding var placement: MiniWidgetPlacement?
    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        let widget = placement.flatMap { registry.miniWidget($0.widgetID) }
        Menu {
            Section("Top Left") {
                Picker("Top Left", selection: widgetID) {
                    Text("None").tag(String?.none)
                    ForEach(registry.miniWidgets) { widget in
                        Label(widget.title, systemImage: widget.systemImage).tag(String?.some(widget.id))
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Top Left: \(widget?.title ?? "None")")
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glassCapsule(size: .regular))
        .fixedSize()
        .accessibilityLabel("Top Left")
        .accessibilityValue(widget?.title ?? "None")
        .sensoryFeedback(.selection, trigger: placement)
    }

    /// Which mini widget, at the smallest size, or None to remove it.
    private var widgetID: Binding<String?> {
        Binding(get: { placement?.widgetID }, set: { id in
            guard id != placement?.widgetID else { return }
            let widget = id.flatMap { registry.miniWidget($0) }
            withAnimation(Theme.Motion.standard) {
                placement = widget.map { MiniWidgetPlacement(widgetID: $0.id, size: .small) }
            }
        })
    }
}

/// The widget gallery for one face: the Smart Stack first, then every widget
/// as a big live preview at the size it will be on this face, its sizes to
/// swipe through, and Add Widget, which is off for a size the face has no room for.
struct FaceWidgetGallerySheet: View {
    /// The face's widgets as saved, in the orientation being arranged.
    let board: FaceWidgetBoard
    var opening: String?
    var size: WidgetSize?
    let onAdd: (WidgetDescriptor, WidgetSize) -> Void
    /// Adds a Smart Stack of these widgets at a size.
    let onAddStack: (WidgetSize, [WidgetDescriptor]) -> Void

    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services

    var body: some View {
        WidgetGallery(
            widgets: registry.widgets, tileSize: { board.grid.tileSize($0) },
            unavailableReason: { _, size in
                board.hasRoom(for: size) ? nil
                    : "No room for a \(size.title.lowercased()) widget here. Move or remove a widget, or pick a smaller size."
            },
            opening: opening, size: size,
            // First, as on iPadOS: the widgets that can say when they matter, at the size shown.
            smartStack: SmartStackOffer(widgets: { WidgetStack.suggested(from: registry.widgets, size: $0) }, onAdd: onAddStack),
            onAdd: onAdd
        ) { widget, size in
            FaceWidgetTile(widget: widget, size: size, isLocked: isLocked(widget))
        }
    }

    /// Personal widgets preview locked until someone is recognized.
    private func isLocked(_ widget: WidgetDescriptor) -> Bool {
        let showPersonal = services.household.isPersonalContentUnlocked || FaceDebugOptions.forcesPersonal
        return FaceWidgetAccess.of(widget, showPersonal: showPersonal, keepsPersonalPlaces: true) == .locked
    }
}
