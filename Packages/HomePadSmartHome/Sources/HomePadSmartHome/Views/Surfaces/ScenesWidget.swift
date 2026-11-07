import HomePadCore
import HomePadUI
import SwiftUI

/// Scenes as a widget, as scene tiles on HomeView: favorites first, then other
/// scenes, every scene the same size, filling the widget, with its whole name.
/// The Home Screen labels the widget, so there is no header taking a row.
///
/// - Small: one tile, or two rows.
/// - Medium: up to three tiles side by side, or four in two rows.
struct ScenesWidget: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    let size: WidgetSize

    var body: some View {
        let scenes = Array(service.scenesFavoritesFirst.prefix(size == .small ? 2 : 4))
        GlassTile {
            if scenes.isEmpty {
                Label("Add scenes in the Home app", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                // Large text can make two rows too tall: then fewer scenes, never cut-off names.
                ViewThatFits(in: .vertical) {
                    layout(scenes)
                    layout(Array(scenes.prefix(size == .small ? 1 : 2)))
                }
            }
        }
    }

    @ViewBuilder
    private func layout(_ scenes: [HomeScene]) -> some View {
        let spacing = Theme.Spacing.controlGap
        if size == .small {
            VStack(spacing: spacing) {
                ForEach(scenes) { SceneButton(scene: $0, style: scenes.count == 1 ? .tile : .row) }
            }
        } else if scenes.count <= 3 {
            HStack(spacing: spacing) {
                ForEach(scenes) { SceneButton(scene: $0, style: .tile) }
            }
        } else {
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach([0, 2], id: \.self) { start in
                    GridRow {
                        ForEach(scenes[start..<min(start + 2, scenes.count)]) { SceneButton(scene: $0, style: .row) }
                    }
                }
            }
        }
    }
}
