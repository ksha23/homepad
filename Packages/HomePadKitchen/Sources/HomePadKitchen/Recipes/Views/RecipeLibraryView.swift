import HomePadCore
import HomePadUI
import SwiftUI

/// The recipe library: one field to search or paste a link, the Discover shelf,
/// and a grid of saved recipes, pinned first. A search replaces the shelf and
/// grid with results until the field is cleared.
struct RecipeLibraryView: View {
    let context: KitchenContext

    var body: some View {
        AppScreen("Recipes", accessory: {
            GlassCapsuleButton("Meal Plan", systemImage: "calendar") { context.showMealPlan() }
        }) {
            RecipeImportBar(context: context)
            if context.search.isActive {
                RecipeSearchResultsView(context: context)
            } else if context.library.recipes.isEmpty, context.discovery.picks.isEmpty, !context.discovery.isLoading {
                EmptyStateView("No Recipes Yet",
                               message: "Search for a recipe, paste a link from any recipe site, share one from your iPhone, or scan a cookbook page.",
                               systemImage: "book.closed",
                               actionTitle: "Add Sample Recipes") { context.library.restoreSamples() }
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            DiscoverShelf(context: context)
                            if !context.library.recipes.isEmpty {
                                savedRecipes(in: proxy.size)
                            }
                        }
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func savedRecipes(in size: CGSize) -> some View {
        let grid = Self.grid(count: context.library.recipes.count, in: size)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("My Recipes")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l), count: grid.columns),
                      spacing: Theme.Spacing.l) {
                ForEach(context.library.recipes) { recipe in
                    Button { context.open(recipe) } label: {
                        RecipeTile(recipe: recipe, library: context.library, height: grid.tileHeight)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: recipe) }
                }
            }
        }
    }

    /// Few recipes get big cards. Larger libraries get more, smaller columns.
    static func grid(count: Int, in size: CGSize) -> (columns: Int, tileHeight: CGFloat) {
        let isWide = size.width > size.height
        let columns: Int = switch count {
        case ...2: 2
        case ...6: isWide ? 3 : 2
        default: isWide ? 4 : 3
        }
        let tileWidth = (size.width - Theme.Spacing.l * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = min(tileWidth * 0.75, max(size.height * 0.56, 260))
        return (columns, max(tileHeight, 220))
    }

    @ViewBuilder
    private func menu(for recipe: Recipe) -> some View {
        Button(recipe.isPinned ? "Unpin" : "Pin", systemImage: recipe.isPinned ? "pin.slash" : "pin") {
            context.library.togglePin(recipe.id)
        }
        ShareLink(item: RecipeShareText.text(for: recipe), subject: Text(recipe.title)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            context.deleteRecipe(recipe.id)
        }
    }
}
