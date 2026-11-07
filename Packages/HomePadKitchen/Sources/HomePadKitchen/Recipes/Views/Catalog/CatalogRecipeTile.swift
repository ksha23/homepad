import HomePadUI
import SwiftUI

extension CatalogRecipe {
    /// The recipe with the smaller photo, for tiles and shelves.
    var tileRecipe: Recipe {
        var recipe = recipe
        recipe.imageURL = thumbnailURL ?? recipe.imageURL
        return recipe
    }
}

/// A search result: the library's tile (photo, title, source and time) with a
/// Saved badge once it is in the library. A tap previews it, and the context
/// menu saves it without opening the preview.
struct CatalogRecipeTile: View {
    let context: KitchenContext
    let result: CatalogRecipe
    let height: CGFloat

    var body: some View {
        let saved = context.savedRecipe(for: result)
        Button { context.preview(result) } label: {
            RecipeTile(recipe: result.tileRecipe, library: context.library, height: height)
                .overlay(alignment: .topTrailing) {
                    if saved != nil {
                        GlassPill("Saved", systemImage: "checkmark")
                            .padding(Theme.Spacing.s)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let saved {
                Button("Open", systemImage: "book") { context.open(saved) }
            } else {
                Button("Save to My Recipes", systemImage: "plus") { context.save(result.recipe, open: false) }
            }
            Button("Preview", systemImage: "eye") { context.preview(result) }
        }
    }
}

/// A Discover pick: square photo with the title and the kind of dish under it.
struct DiscoverTile: View {
    let context: KitchenContext
    let result: CatalogRecipe
    let width: CGFloat

    var body: some View {
        ArtworkTile(title: result.recipe.title, subtitle: result.kindLine ?? RecipeMetadata.line(for: result.recipe),
                    width: width, action: { context.preview(result) }) {
            RecipeHeroImage(recipe: result.tileRecipe, library: context.library)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .contextMenu {
            Button("Save to My Recipes", systemImage: "plus") { context.save(result.recipe, open: false) }
        }
    }
}
