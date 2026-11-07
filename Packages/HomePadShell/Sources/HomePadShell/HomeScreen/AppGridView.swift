import HomePadCore
import HomePadUI
import SwiftUI

/// Every app, grouped by category, opened by swiping up on the Home Screen.
/// Includes apps the member removed from their Home Screen.
struct AppGridView: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.l)]

    var body: some View {
        let access = PersonalAccess(household)
        let groups = AppCategory.allCases.compactMap { category -> (AppCategory, [(AppDescriptor, AppIconTile.Badge)])? in
            let apps = registry.apps.filter { $0.category == category }.compactMap { app in access.badge(for: app).map { (app, $0) } }
            return apps.isEmpty ? nil : (category, apps)
        }
        GlassPanel(cornerRadius: Theme.Radius.tile, padding: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack {
                    Text("All Apps").font(.screenTitle)
                    Spacer()
                    CloseButton { navigator.panel = nil }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        ForEach(groups, id: \.0) { category, apps in
                            SectionHeader(category.title)
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                                ForEach(apps, id: \.0.id) { app, badge in
                                    Button { navigator.open(appID: app.id) } label: {
                                        AppIconTile(title: app.title, systemImage: app.systemImage, tint: app.tint,
                                                    iconSize: Theme.Size.appIcon, badge: badge, isOnWallpaper: false)
                                            .recordsIconFrame(ZoomSourceID.grid(app.id), iconSize: Theme.Size.appIcon)
                                            .opacity(navigator.isIconHidden(ZoomSourceID.grid(app.id)) ? 0 : 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Theme.Spacing.l)
        .nightModeAware()
    }
}

extension AppCategory {
    /// Section title in the app grid.
    var title: String {
        switch self {
        case .home: "Home"
        case .media: "Entertainment"
        case .communication: "Communication"
        case .kitchen: "Kitchen"
        case .productivity: "Productivity"
        case .camera: "Camera"
        case .system: "System"
        }
    }
}
