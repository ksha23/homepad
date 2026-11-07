import HomePadCore
import HomePadUI
import SwiftUI

/// A catalog recipe before it is saved: photo, facts, ingredients and steps,
/// with Save as the header's one action. Once saved the header opens the
/// library copy instead. The title sits under the photo, like the recipe
/// card's, so the header shows only its buttons.
struct RecipePreviewSheet: View {
    let context: KitchenContext
    let result: CatalogRecipe
    @Environment(\.dismiss) private var dismiss

    private var recipe: Recipe { result.recipe }

    var body: some View {
        SheetScreen("") {
            saveButton
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    section("Ingredients", systemImage: "checklist") {
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                                Text("•").bold().foregroundStyle(.orange)
                                Text(line)
                            }
                        }
                    }
                    section("Steps", systemImage: "list.number") {
                        ForEach(recipe.steps) { step in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                                Text("\(step.number)").bold().foregroundStyle(.orange).monospacedDigit()
                                Text(step.text)
                            }
                        }
                    }
                    if let url = recipe.sourceURL {
                        Link(destination: url) {
                            Label("Recipe and photo from \(context.catalog.name)", systemImage: "safari")
                        }
                        .font(.footnote)
                    }
                }
                .padding([.horizontal, .bottom], Theme.Spacing.l)
            }
        }
        .presentationSizing(.page)
        .presentationBackground(.ultraThinMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RecipeHeroImage(recipe: recipe, library: context.library)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Text(recipe.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(([RecipeMetadata.line(for: recipe)] + [result.kindLine].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.title3)
                .foregroundStyle(.secondary)
            if let summary = recipe.summary {
                Text(summary).font(.headline).foregroundStyle(.secondary)
            }
            if context.savedRecipe(for: result) != nil {
                Label("Saved to My Recipes", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title, systemImage: systemImage)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) { content() }
                .font(.title3)
        }
    }

    /// The header's action: Save, then Open once it is in the library.
    @ViewBuilder
    private var saveButton: some View {
        if let saved = context.savedRecipe(for: result) {
            GlassCapsuleButton("Open in My Recipes", systemImage: "book") {
                dismiss()
                context.open(saved)
            }
        } else {
            GlassCapsuleButton("Save to My Recipes", systemImage: "plus", isProminent: true, tint: .orange) {
                context.save(recipe, open: false)
            }
        }
    }
}
