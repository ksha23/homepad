import HomePadUI
import SwiftUI

/// What the library shows while the field holds a search: saved recipes that
/// match first, then the catalog's results, which load as you type. Searching,
/// no results and offline each have their own calm state.
struct RecipeSearchResultsView: View {
    let context: KitchenContext

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    let saved = savedMatches
                    if !saved.isEmpty { savedSection(saved, in: proxy.size) }
                    catalogSection(in: proxy.size, hasSavedMatches: !saved.isEmpty)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// Saved recipes whose title has every searched word.
    private var savedMatches: [Recipe] {
        let words = context.search.query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return context.library.recipes.filter { recipe in
            let title = recipe.title.lowercased()
            return words.allSatisfy { title.contains($0) }
        }
    }

    private func savedSection(_ recipes: [Recipe], in size: CGSize) -> some View {
        let grid = RecipeLibraryView.grid(count: max(recipes.count, 3), in: size)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("In My Recipes", systemImage: "book.closed")
            LazyVGrid(columns: columns(grid.columns), spacing: Theme.Spacing.l) {
                ForEach(recipes) { recipe in
                    Button { context.open(recipe) } label: {
                        RecipeTile(recipe: recipe, library: context.library, height: grid.tileHeight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func catalogSection(in size: CGSize, hasSavedMatches: Bool) -> some View {
        let search = context.search
        let name = context.catalog.name
        switch search.phase {
        case .idle:
            Text("Keep typing to search \(name).")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .searching:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("Searching \(name)…")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: size.height * 0.4)
        case .results(let results):
            let grid = RecipeLibraryView.grid(count: results.count, in: size)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("From \(name)", systemImage: "globe")
                LazyVGrid(columns: columns(grid.columns), spacing: Theme.Spacing.l) {
                    ForEach(results) { CatalogRecipeTile(context: context, result: $0, height: grid.tileHeight) }
                }
                Text("Recipes and photos from \(name). Tap one to preview it, then save it to My Recipes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.s)
            }
        case .noResults:
            if !hasSavedMatches {
                EmptyStateView("No Results",
                               message: "\(name) has no recipes for \"\(search.query)\". Try one main ingredient, such as chicken or lentils.",
                               systemImage: "magnifyingglass")
                    .frame(minHeight: size.height * 0.6)
            }
        case .failed(let message, let isOffline):
            EmptyStateView(isOffline ? "You're Offline" : "Search Unavailable",
                           message: isOffline ? "Recipes can be searched again when HomePad is back online. Saved recipes still work." : message,
                           systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle",
                           actionTitle: "Try Again") { Task { await search.run(search.query) } }
                .frame(minHeight: size.height * 0.6)
        }
    }

    private func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l), count: count)
    }
}
