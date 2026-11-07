import HomePadCore
import HomePadUI
import SwiftUI

/// A widget or a widget stack on the Home Screen with its name underneath,
/// the way HomeView labels widgets. Locked personal widgets show a blurred
/// placeholder. In edit mode a tap on a widget with settings opens Edit
/// Widget, and a tap on a stack opens Edit Stack, as on iPadOS.
struct WidgetTileView: View {
    /// What the tile holds.
    enum Content {
        /// One widget with its own settings (`HomeScreenItem.settings`).
        case widget(WidgetDescriptor, settings: WidgetSettings, isLocked: Bool)
        /// A widget stack: its widgets that show, under the stack's item ID.
        case stack(id: String, members: [HomeTile.StackMember], smartRotate: Bool)
    }

    @Environment(ShellNavigator.self) private var navigator
    @Environment(AppServices.self) private var services
    @Environment(\.backdropScheme) private var backdropScheme
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    let size: WidgetSize
    let labelHeight: CGFloat
    let isEditing: Bool
    /// True when it has more than one size to step through in edit mode.
    let canResize: Bool
    let onRemove: () -> Void
    let onResize: () -> Void
    /// Opens Edit Widget or Edit Stack. Nil for a widget without settings or a locked one.
    var onEdit: (() -> Void)?
    /// The id the widget reports itself under (`ZoomSource`): an app opened from it zooms out of it and closes
    /// back into it, not into the app's icon, which may not even be on the Home Screen.
    var zoomSourceID: String?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
    }

    /// The widget on top: the widget itself, or the stack's widget that shows now.
    private var shown: (widget: WidgetDescriptor, isLocked: Bool)? {
        switch content {
        case .widget(let widget, _, let isLocked):
            return (widget, isLocked)
        case .stack(let id, let members, _):
            let shownID = services.widgetStacks.shownMemberID(in: id)
            return (members.first { $0.member.id == shownID } ?? members.first).map { ($0.widget, $0.isLocked) }
        }
    }

    private var isStack: Bool {
        if case .stack = content { return true }
        return false
    }

    var body: some View {
        let shown = shown
        VStack(spacing: Theme.Spacing.xs) {
            // The overlay takes exactly the space the tile offers, so a widget
            // that wants more (larger text) is clipped instead of pushing its
            // label out of the cell.
            Color.clear
                .overlay { tile }
                .contentShape(shape)
                // The window lands on the tile. A touch on the name under it, which opens the app too, counts as
                // the widget's, so the app comes out of the widget rather than out of its icon or the screen's center.
                .zoomSource(zoomSourceID ?? "", isEnabled: zoomSourceID != nil) { [labelHeight] tile in
                    ZoomSource(frame: tile, shape: .surface(cornerRadius: Theme.Radius.tile),
                               hitFrame: CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height + labelHeight))
                }
                // A tap outside the widget's own buttons opens its app, for a stack
                // the app of the widget on top. A locked personal widget opens it
                // too, which asks to recognize the person. In edit mode it opens
                // Edit Widget for a widget with settings, and Edit Stack for a
                // stack. For other widgets it is off there, where it would do
                // nothing and, like the icons' button, could hold off the press
                // that lifts the widget (`HomeReorderGesture`). A swipe on a stack
                // is not a tap, so flipping it opens nothing.
                .gesture(TapGesture().onEnded {
                    if isEditing {
                        onEdit?()
                    } else if let appID = shown?.widget.opensAppID {
                        navigator.open(appID: appID)
                    }
                }, isEnabled: !isEditing || onEdit != nil)
                .accessibilityActions {
                    if isEditing, let onEdit {
                        Button(isStack ? "Edit Stack" : "Edit Widget", action: onEdit)
                    }
                }
            .overlay(alignment: .topLeading) {
                if isEditing {
                    RemoveBadge(isStack ? "Remove Stack" : "Remove \(shown?.widget.title ?? "Widget")", action: onRemove)
                        .offset(x: -10, y: -10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isEditing && canResize {
                    GlassIconButton("arrow.up.left.and.arrow.down.right",
                                    label: "Change size of \(isStack ? "Stack" : shown?.widget.title ?? "Widget")",
                                    size: Theme.Size.minTapTarget, action: onResize)
                        .padding(Theme.Spacing.s)
                }
            }
            Text(shown?.widget.title ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .wallpaperLabelShadow()
                .frame(minHeight: labelHeight - Theme.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(Theme.Motion.standard, value: shown?.widget.id)
        }
    }

    @ViewBuilder
    private var tile: some View {
        switch content {
        case .widget(let widget, let settings, let isLocked):
            Group {
                if isLocked {
                    lockedPlaceholder(widget)
                } else {
                    widget.makeView(size)
                        .environment(\.widgetSettings, settings)
                        .allowsHitTesting(!isEditing)
                }
            }
            .clipShape(shape)
        case .stack(let id, let members, let smartRotate):
            // The stack rounds itself and draws its dots beside its edge, so it is not clipped here.
            let items = members.map { WidgetStackItem(member: $0.member, widget: $0.widget, isAvailable: !$0.isLocked) }
            WidgetStackView(stackID: id, items: items, smartRotate: smartRotate, isInteractive: !isEditing) { item in
                if item.isAvailable {
                    item.widget.makeView(size)
                        .environment(\.widgetSettings, item.member.settings ?? WidgetSettings())
                } else {
                    lockedPlaceholder(item.widget)
                }
            }
            .allowsHitTesting(!isEditing)
        }
    }

    private func lockedPlaceholder(_ widget: WidgetDescriptor) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "lock.fill").font(.title)
                if size != .small {
                    Text("Recognition required").font(.headline)
                }
            }
            .foregroundStyle(.secondary)
        }
        // Glass on the wallpaper, light or dark by it like the widgets beside it.
        .environment(\.colorScheme, backdropScheme ?? colorScheme)
        .accessibilityLabel("\(widget.title), locked until you are recognized")
    }
}
