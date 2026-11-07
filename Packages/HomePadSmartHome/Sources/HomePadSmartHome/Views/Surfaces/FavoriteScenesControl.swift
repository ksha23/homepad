import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center tile (2x2) with up to four scenes, one full-width row each:
/// the favorites, then other scenes, so it has scenes before any is a favorite.
struct FavoriteScenesControl: View {
    @Environment(UnifiedSmartHomeService.self) private var service

    var body: some View {
        let scenes = Array(service.scenesFavoritesFirst.prefix(4))
        if scenes.isEmpty {
            Text("No Scenes").font(.headline).foregroundStyle(.secondary)
        } else {
            VStack(spacing: Theme.Spacing.controlGap) {
                ForEach(scenes) { SceneButton(scene: $0, style: .row) }
            }
            .nightModeAware()
        }
    }
}
