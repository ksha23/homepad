import HomePadCore
import HomePadUI
import SwiftUI

/// The Home app's way to every scene, like the Scenes link in Apple Home: a
/// compact "Scenes" capsule that opens a list of all of them. A row runs its
/// scene, and its star adds the scene to the favorites the Home app shows.
struct ScenesButton: View {
    @State private var isShowingList = false

    var body: some View {
        GlassCapsuleButton("Scenes", systemImage: "sparkles", size: .large) { isShowingList = true }
            .accessibilityLabel("Scenes")
            .accessibilityHint("Shows every scene")
            .popover(isPresented: $isShowingList) {
                SceneList().presentationCompactAdaptation(.popover)
            }
    }
}

/// Every scene, one row each, with a star for the Home app's favorite scenes.
struct SceneList: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    private let rowHeight = Theme.Size.tapTarget
    private let spacing = Theme.Spacing.controlGap

    var body: some View {
        let scenes = service.scenes
        let height = CGFloat(scenes.count) * (rowHeight + spacing) - spacing + Theme.Spacing.m * 2
        ScrollView {
            VStack(spacing: spacing) {
                ForEach(scenes) { scene in
                    HStack(spacing: Theme.Spacing.s) {
                        SceneButton(scene: scene, style: .row)
                        favoriteButton(for: scene)
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Popovers size to their content, and a scroll view has no height of its own.
        .frame(width: 360, height: min(max(height, 0), 560))
        .environment(\.controlCornerRadius, Theme.Radius.tileControl)
        .nightModeAware()
    }

    private func favoriteButton(for scene: HomeScene) -> some View {
        let isFavorite = service.favoriteSceneIDs.contains(scene.id)
        return GlassIconButton(
            isFavorite ? "star.fill" : "star",
            label: isFavorite ? "Remove \(scene.name) from Favorites" : "Add \(scene.name) to Favorites",
            size: Theme.Size.tapTarget,
            tint: isFavorite ? .yellow : nil
        ) {
            service.setFavoriteScene(scene.id, isFavorite: !isFavorite)
        }
    }
}
