import HomePadCore
import HomePadUI
import SwiftUI

/// Home Screen and Modular face widget: one recipe a day from the library,
/// pinned recipes first. Tapping opens its card. It looks for the day's recipe
/// again at midnight, and when the library changes.
struct RecipeOfTheDayWidget: View {
    let size: WidgetSize
    let context: KitchenContext
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayCondition) private var displayCondition

    var body: some View {
        TimelineView(MidnightSchedule(isPaused: isThumbnail || displayCondition == .sleeping)) { timeline in
            if let recipe = context.library.recipeOfTheDay(on: timeline.date) {
                content(recipe)
                    .contentShape(Rectangle())
                    .onTapGesture { context.open(recipe, bringToFront: true) }
            } else {
                GlassTile {
                    Label("No recipes yet", systemImage: "book.closed").font(.headline)
                }
            }
        }
    }

    private func content(_ recipe: Recipe) -> some View {
        ZStack(alignment: .bottomLeading) {
            RecipeHeroImage(recipe: recipe, library: context.library)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Capitals at Subheadline, like `StatusBadge`, shrinking only
                // as far as the small tile needs.
                Text("Recipe of the Day")
                    .font(.subheadline.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(recipe.title)
                    .font(size == .small ? .headline : .title2.bold())
                    .lineLimit(2)
                if size != .small {
                    Text(RecipeMetadata.line(for: recipe))
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        // The text sits on the photo's dark gradient in every appearance.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
    }
}
