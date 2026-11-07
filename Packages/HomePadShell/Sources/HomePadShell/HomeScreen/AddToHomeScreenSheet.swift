import HomePadCore
import HomePadUI
import SwiftUI

/// Adding to the Home Screen from edit mode, one sheet per kind as the edit
/// bar's Add Widget and Add App buttons ask: the widget gallery
/// (`WidgetGallery`, the same one the face editor uses: every widget live,
/// then its sizes to swipe through) or the apps that are not on the Home
/// Screen. Adding one puts it on the page on screen.
///
/// A widget with settings can be added again, since each copy keeps its own
/// (two Reminders widgets on two lists). One without settings would only
/// repeat itself, so it is offered while it is not on the Home Screen. The
/// Smart Stack comes first, as on iPadOS.
struct AddToHomeScreenSheet: View {
    enum Kind { case widgets, apps }

    let kind: Kind
    let memberID: HouseholdMember.ID?
    let page: Int
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(HomeScreenLayoutStore.self) private var layouts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch kind {
        case .widgets:
            WidgetGallery(widgets: widgets, tileSize: previewSize,
                          empty: ("Every Widget Is Here", "Every widget is already on your Home Screen."),
                          smartStack: smartStack) { widget, size in
                add(.newWidget(widget.id, size: size))
            } preview: { widget, size in
                widget.makeView(size)
            }
        case .apps:
            SheetScreen("Add App") {
                ScrollView {
                    appGrid.padding(Theme.Spacing.l)
                }
            }
        }
    }

    /// Widgets this person may see that are not on the Home Screen yet, and
    /// every widget with settings.
    private var widgets: [WidgetDescriptor] {
        let layout = layouts.layout(for: memberID)
        let access = PersonalAccess(household)
        return registry.widgets.filter {
            ($0.hasSettings || !layout.containsWidget($0.id)) && access.visibility(isPersonal: $0.isPersonal) != .hidden
        }
    }

    /// The Smart Stack, first in the gallery as on iPadOS: a stack of the
    /// widgets this person may see that can say when they matter
    /// (`WidgetStack.suggested`), whether or not they are on the Home Screen already.
    private var smartStack: SmartStackOffer {
        let access = PersonalAccess(household)
        let visible = registry.widgets.filter { access.visibility(isPersonal: $0.isPersonal) != .hidden }
        return SmartStackOffer(widgets: { WidgetStack.suggested(from: visible, size: $0) }) { size, widgets in
            if let item = HomeScreenItem.stack(.of(widgets.map(\.id)), size: size) { add(item) }
        }
    }

    @ViewBuilder
    private var appGrid: some View {
        let layout = layouts.layout(for: memberID)
        let access = PersonalAccess(household)
        let apps = registry.apps.filter { !layout.contains(HomeScreenItem.app($0.id).id) && access.badge(for: $0) != nil }
        if apps.isEmpty {
            EmptyStateView("Every App Is Here", message: "Every app is already on your Home Screen.",
                           systemImage: "checkmark.circle")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.l)], spacing: Theme.Spacing.l) {
                ForEach(apps) { app in
                    Button { add(.app(app.id)) } label: {
                        AppIconTile(title: app.title, systemImage: app.systemImage, tint: app.tint, iconSize: 80, isOnWallpaper: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(app.title)")
                }
            }
        }
    }

    /// The size each widget size is drawn at in the gallery: about its size on
    /// the Home Screen, 160 point cells 20 points apart (small 160 by 160,
    /// medium 340 by 160, large 340 by 340, tall 340 by 520).
    private func previewSize(_ size: WidgetSize) -> CGSize {
        CGSize(width: Self.span(size.columns), height: Self.span(size.rows))
    }

    private static func span(_ cells: Int) -> CGFloat {
        CGFloat(cells) * 160 + CGFloat(cells - 1) * 20
    }

    private func add(_ item: HomeScreenItem) {
        layouts.update(for: memberID) { $0.add(item, toPage: page) }
        dismiss()
    }
}
