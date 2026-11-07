import HomePadCore
import HomePadUI
import SwiftUI

/// An app icon or widget on the Home Screen. Outside edit mode it opens the
/// app (through the recognition gate if needed) and long-press shows the
/// iPadOS context menu. In edit mode it jiggles and can be removed or
/// resized, a short press lifts it to move it (`HomeReorderSession`), a tap
/// on a widget with settings opens Edit Widget, and a tap on a stack Edit Stack.
struct HomeTileView: View {
    let tile: HomeTile
    let metrics: HomeGridMetrics
    let memberID: HouseholdMember.ID?
    /// Drawn under the finger while it is moved: still, and without edit controls.
    var isLifted = false
    /// VoiceOver's way to reorder in edit mode: one place earlier (-1) or later (1).
    var onNudge: ((Int) -> Void)?
    /// Opens Edit Widget for this widget, in edit mode.
    var onEditWidget: (() -> Void)?
    @Environment(ShellNavigator.self) private var navigator
    @Environment(HomeScreenLayoutStore.self) private var layouts

    var body: some View {
        if isLifted {
            // Paused rather than off, so it keeps the frosted material of the
            // jiggling tiles instead of switching to glass.
            content.jiggle(true, isPaused: true)
        } else if navigator.isEditingHomeScreen {
            content
                .jiggle(true)
                .accessibilityAction(named: "Move Earlier") { onNudge?(-1) }
                .accessibilityAction(named: "Move Later") { onNudge?(1) }
        } else if tile.item.kind == .widget {
            // Holding a widget enters edit mode, as on empty space. Widgets have no
            // context menu: its press competed with sliding a light's level in
            // Favorites. This hold has normal priority, so a control inside the
            // widget that claims the press first (a light row's slider) keeps it,
            // and edit mode comes from the widget's other parts and its name.
            content
                .gesture(LongPressGesture(minimumDuration: Self.editHold).onEnded { _ in navigator.isEditingHomeScreen = true })
        } else {
            // App icons carry their menu on the icon itself (`appIcon`).
            content
        }
    }

    /// How long a still press takes to enter edit mode, on widgets and empty space alike.
    static let editHold: Double = 0.6

    /// Edit mode and its controls, except on the lifted copy.
    private var isEditing: Bool { navigator.isEditingHomeScreen && !isLifted }

    @ViewBuilder
    private var content: some View {
        switch tile.content {
        case .app(let app):
            let icon = appIcon(app)
                .recordsIconFrame(app.id, iconSize: metrics.iconSize, isEnabled: !isLifted)
                // Hidden while its app zooms out of it or into it: the window is the icon then.
                .opacity(navigator.isIconHidden(app.id) ? 0 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if navigator.isEditingHomeScreen {
                // No button in edit mode, where a press lifts the icon instead
                // (`HomeReorderGesture`): a held button kept that press from starting.
                icon.accessibilityAddTraits(.isButton)
            } else {
                Button { navigator.open(appID: app.id) } label: { icon }
                    .buttonStyle(.plain)
            }
        case .widget(let widget, let size):
            WidgetTileView(
                content: .widget(widget, settings: tile.item.settings ?? WidgetSettings(), isLocked: tile.isLocked),
                size: size, labelHeight: metrics.widgetLabelHeight, isEditing: isEditing,
                canResize: widget.supportedSizes.count > 1,
                onRemove: remove, onResize: { cycleSize(widget.supportedSizes, from: size) },
                // A locked personal widget keeps its settings out of sight.
                onEdit: widget.hasSettings && !tile.isLocked ? onEditWidget : nil,
                // A lifted copy under the finger is not where the widget lives.
                zoomSourceID: isLifted ? nil : ZoomSourceID.widget(tile.id)
            )
        case .stack(let members, let size):
            // A stack takes the sizes all its widgets come in.
            let sizes = WidgetStack.sizes(supportedByAll: members.map(\.widget.supportedSizes))
            WidgetTileView(
                content: .stack(id: tile.id, members: members, smartRotate: tile.item.stack?.smartRotate ?? true),
                size: size, labelHeight: metrics.widgetLabelHeight, isEditing: isEditing,
                canResize: sizes.count > 1,
                onRemove: remove, onResize: { cycleSize(sizes, from: size) },
                // Edit Stack shows each widget's name, and keeps a locked one's settings closed itself.
                onEdit: onEditWidget,
                zoomSourceID: isLifted ? nil : ZoomSourceID.widget(tile.id)
            )
        }
    }

    private func appIcon(_ app: AppDescriptor) -> AppIconTile {
        let icon = AppIconTile(
            title: app.title, systemImage: app.systemImage, tint: app.tint, iconSize: metrics.iconSize,
            badge: isEditing ? .remove : (tile.isLocked ? .locked : app.countBadge),
            onRemove: remove
        )
        return navigator.isEditingHomeScreen || isLifted ? icon : icon.iconMenu { menu }
    }

    /// App icons' context menu. Widgets enter edit mode instead (see `body`).
    @ViewBuilder
    private var menu: some View {
        Button("Edit Home Screen", systemImage: "apps.ipad") {
            // After the menu has closed: while it closes, iPadOS draws the lifted
            // icon above everything, and the new remove badge showed behind it.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                navigator.isEditingHomeScreen = true
            }
        }
        Button(role: .destructive, action: remove) {
            Label("Remove App", systemImage: "minus.circle")
        }
    }

    private func remove() {
        withAnimation(Theme.Motion.standard) { edit { $0.remove(tile.id) } }
    }

    private func cycleSize(_ sizes: [WidgetSize], from size: WidgetSize) {
        guard let index = sizes.firstIndex(of: size), sizes.count > 1 else { return }
        let next = sizes[(index + 1) % sizes.count]
        withAnimation(Theme.Motion.settle) { edit { $0.resize(tile.id, to: next) } }
    }

    private func edit(_ change: (inout HomeScreenLayout) -> Void) {
        layouts.update(for: memberID, change)
    }
}
