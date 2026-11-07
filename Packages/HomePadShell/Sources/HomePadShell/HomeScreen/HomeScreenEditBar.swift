import HomePadCore
import HomePadUI
import SwiftUI

/// The toolbar shown in Home Screen edit mode, in place of the greeting:
/// the header's mini widget to resize or remove, then add a widget, add an
/// app, change wallpaper, add a page, and Done.
///
/// HomePad's own glass capsules, `.primary` on glass with Done as the one
/// prominent action. The system glass style drew its titles in the accent
/// blue, which was hard to read on the frosted glass. Where the titles do not
/// fit (portrait), the actions become round symbol buttons.
///
/// The mini widget stays where it lives, at the leading end where the
/// header's lines were, so editing it looks like editing a widget. It gets
/// the room the actions leave and shrinks to fit, as in the header. Removed,
/// it comes back with Add Glance, first among the actions. With more than one
/// mini widget registered, that action asks which one.
struct HomeScreenEditBar: View {
    let miniWidget: MiniWidgetPlacement?
    /// The header lines' point size, which the mini widget shares.
    let textSize: CGFloat
    let onMiniWidgetChange: (MiniWidgetPlacement?) -> Void
    let onAddWidget: () -> Void
    let onAddApp: () -> Void
    let onWallpaper: () -> Void
    let onNewPage: () -> Void
    let onDone: () -> Void

    @Environment(ModuleRegistry.self) private var registry
    @State private var isChoosingMiniWidget = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let miniWidget, let widget = registry.miniWidget(miniWidget.widgetID) {
                HeaderMiniWidgetEditItem(widget: widget, placement: miniWidget, textSize: textSize,
                                         onChange: onMiniWidgetChange)
                    .padding(.trailing, Theme.Spacing.l - Theme.Spacing.s)
                    .layoutPriority(-1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(actions, id: \.title) { action in
                        GlassCapsuleButton(action.title, systemImage: action.systemImage, size: .regular, action: action.perform)
                    }
                }
                .fixedSize()
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(actions, id: \.title) { action in
                        GlassIconButton(action.systemImage, label: action.title, action: action.perform)
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
                .layoutPriority(-2)
            GlassCapsuleButton("Done", size: .regular, isProminent: true, action: onDone)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: Theme.Size.tapTarget)
        .confirmationDialog("Add Mini Widget", isPresented: $isChoosingMiniWidget) {
            ForEach(registry.miniWidgets) { widget in
                Button(widget.title) { add(widget) }
            }
        }
    }

    private var actions: [(title: String, systemImage: String, perform: () -> Void)] {
        var actions: [(title: String, systemImage: String, perform: () -> Void)] = []
        if let add = addMiniWidgetAction {
            actions.append(add)
        }
        return actions + [("Add Widget", "plus", onAddWidget), ("Add App", "plus.app", onAddApp),
                          ("Wallpaper", "photo.on.rectangle", onWallpaper), ("New Page", "rectangle.badge.plus", onNewPage)]
    }

    /// Brings a mini widget back while the header has none, or one whose
    /// module is gone: "Add Glance" while the glance is the only one, or a
    /// choice of them once there are more.
    private var addMiniWidgetAction: (title: String, systemImage: String, perform: () -> Void)? {
        let shown = miniWidget.flatMap { registry.miniWidget($0.widgetID) }
        let available = registry.miniWidgets
        guard shown == nil, let first = available.first else { return nil }
        if available.count == 1 {
            return ("Add \(first.title)", first.systemImage, { add(first) })
        }
        return ("Add Mini Widget", "plus.rectangle", { isChoosingMiniWidget = true })
    }

    /// Puts a mini widget in the header at its smallest size.
    private func add(_ widget: MiniWidgetDescriptor) {
        withAnimation(Theme.Motion.settle) {
            onMiniWidgetChange(MiniWidgetPlacement(widgetID: widget.id, size: widget.supportedSizes[0]))
        }
    }
}
