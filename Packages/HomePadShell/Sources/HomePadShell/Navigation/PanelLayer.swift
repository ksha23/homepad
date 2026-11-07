import HomePadUI
import SwiftUI

/// Draws the open panel (Control Center, People menu or app grid) over a
/// backdrop. Tapping the backdrop closes it.
///
/// Control Center stays dark in either appearance, as on iPadOS: a dimmed
/// blur with dark glass tiles and white symbols. The People menu and the app
/// grid follow the appearance.
struct PanelLayer: View {
    @Environment(ShellNavigator.self) private var navigator

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let panel = navigator.panel {
                backdrop(for: panel)
                    .transition(.opacity)
                    .onTapGesture { navigator.panel = nil }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Close")
                switch panel {
                case .controlCenter:
                    ControlCenterView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                case .people:
                    PeopleMenuView()
                        .padding(.top, 96)
                        .padding(.trailing, Theme.Spacing.l)
                        .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
                case .appGrid:
                    AppGridView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func backdrop(for panel: ShellNavigator.Panel) -> some View {
        switch panel {
        case .people:
            Color.black.opacity(0.25).ignoresSafeArea()
        case .controlCenter:
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.3)).ignoresSafeArea()
                .environment(\.colorScheme, .dark)
        case .appGrid:
            // Frosted toward the page color: dark in Dark, light in Light.
            Rectangle().fill(.ultraThinMaterial).overlay(Color.screenBackground.opacity(0.3)).ignoresSafeArea()
        }
    }
}
