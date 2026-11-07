import HomePadUI
import SwiftUI

/// A recipe in the library grid: photo, title and quick facts.
struct RecipeTile: View {
    let recipe: Recipe
    let library: RecipeLibrary
    var height: CGFloat = 260

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeHeroImage(recipe: recipe, library: library)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(recipe.title)
                    .font(height >= 360 ? .largeTitle.bold() : .title2.bold())
                    .lineLimit(2)
                Text(RecipeMetadata.line(for: recipe))
                    .font(height >= 360 ? .title3 : .tileDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(height >= 360 ? Theme.Spacing.l : Theme.Spacing.m)
        }
        .overlay(alignment: .topTrailing) {
            if recipe.isPinned {
                Image(systemName: "pin.fill")
                    .font(.headline)
                    .padding(Theme.Spacing.s)
                    .glassEffect(.regular, in: .circle)
                    .padding(Theme.Spacing.s)
                    .accessibilityLabel("Pinned")
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        // The text and the pin sit on the photo's dark gradient in every appearance.
        .environment(\.colorScheme, .dark)
    }
}
