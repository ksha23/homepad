import HomePadUI
import SwiftUI

/// Picks a saved recipe for a day of the plan: My Recipes as tiles, with a
/// search field first. A tap plans it and closes the sheet, so the sheet has
/// no action of its own. Imported and scanned recipes are in My Recipes too.
struct MealPickerSheet: View {
    let context: KitchenContext
    let day: MealDay
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScreen("Add to \(MealPlanFormat.dayName(day))") {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        GlassSearchField("Search My Recipes", text: $query)
                        if recipes.isEmpty {
                            EmptyStateView(query.isEmpty ? "No Recipes Yet" : "No Matches",
                                           message: query.isEmpty
                                               ? "Save a recipe from the search, a link or a scan, then plan it here."
                                               : "No saved recipe has \"\(query)\" in its title.",
                                           systemImage: "book.closed")
                                .padding(.top, Theme.Spacing.xl)
                        } else {
                            grid(in: proxy.size)
                        }
                    }
                    .padding([.horizontal, .bottom], Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationSizing(.page)
    }

    /// The library's own grid, sized to the sheet.
    private func grid(in size: CGSize) -> some View {
        let layout = RecipeLibraryView.grid(count: recipes.count, in: CGSize(width: size.width - Theme.Spacing.l * 2, height: size.height))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l), count: layout.columns),
                         spacing: Theme.Spacing.l) {
            ForEach(recipes) { recipe in
                Button {
                    context.plan(recipe, on: day)
                    dismiss()
                } label: {
                    RecipeTile(recipe: recipe, library: context.library, height: layout.tileHeight)
                }
                .buttonStyle(.pressable(scale: 0.97))
                .accessibilityHint("Plans it for \(MealPlanFormat.fullDay(day)).")
            }
        }
    }

    /// Pinned first, then newest, like the library. Every word must be in the title.
    private var recipes: [Recipe] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return context.library.recipes }
        return context.library.recipes.filter { recipe in
            let title = recipe.title.lowercased()
            return words.allSatisfy { title.contains($0) }
        }
    }
}
