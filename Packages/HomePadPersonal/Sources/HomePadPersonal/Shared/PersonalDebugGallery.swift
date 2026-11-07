import HomePadCore
import HomePadUI
import SwiftUI

#if DEBUG
/// Debug-only screens for checking the module's widgets and settings pane in
/// the simulator before the real shell hosts them. Registered only when the
/// app launches with `-HomePadPersonalGallery YES`, then opened with
/// `-HomePadOpenApp personal.widgets` or `-HomePadOpenApp personal.settings`.
@MainActor
enum PersonalDebugGallery {
    static func register(in registry: ModuleRegistry, personal: PersonalServices) {
        guard PersonalDebugLaunch.showsGallery else { return }
        registry.register(app: AppDescriptor(id: "personal.widgets", title: "Widgets", systemImage: "square.grid.2x2", category: .system, sortOrder: 900) {
            WidgetGallery(widgets: registry.widgets.filter { $0.id.hasPrefix("personal.") }).personalEnvironment(personal)
        })
        registry.register(app: AppDescriptor(id: "personal.settings", title: "Personal Info", systemImage: "gearshape", category: .system, sortOrder: 901) {
            NavigationStack { PersonalSettingsPane() }.personalEnvironment(personal)
        })
    }
}

/// Every widget at small, medium and large sizes on a 180 point grid.
private struct WidgetGallery: View {
    let widgets: [WidgetDescriptor]
    private let unit: CGFloat = 170

    var body: some View {
        AppScreen("Widgets") {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(widgets) { widget in
                        SectionHeader(widget.title, systemImage: widget.systemImage)
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            widget.makeView(.small).frame(width: unit, height: unit)
                            widget.makeView(.medium).frame(width: unit * 2 + Theme.Spacing.m, height: unit)
                            widget.makeView(.large).frame(width: unit * 2 + Theme.Spacing.m, height: unit * 2 + Theme.Spacing.m)
                        }
                    }
                }
            }
        }
    }
}
#endif
