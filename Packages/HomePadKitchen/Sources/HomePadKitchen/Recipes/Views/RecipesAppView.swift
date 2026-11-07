import HomePadCore
import HomePadUI
import SwiftUI

/// The Recipes app: the library, a recipe's card, cooking mode, or the meal plan.
///
/// `KitchenContext` outlives the app's view, so it reopens on the same card or
/// cooking step, with the same servings and ticked ingredients. After a
/// relaunch it reopens the recipe, and cooking mode on its step while that is
/// recent, or the meal plan (`KitchenAppState`).
struct RecipesAppView: View {
    let context: KitchenContext

    var body: some View {
        ZStack {
            switch (context.screen, context.session) {
            case (.cooking, let session?):
                CookingModeView(context: context, session: session)
                    .transition(.opacity)
            case (.recipe, let session?):
                RecipeCardView(context: context, session: session)
                    .transition(.opacity)
            case (.mealPlan, _):
                MealPlanView(context: context)
                    .transition(.opacity)
            default:
                RecipeLibraryView(context: context)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.screen, value: context.screen)
        .sheet(item: previewBinding) { result in
            RecipePreviewSheet(context: context, result: result)
        }
        .onAppear {
            context.isRecipesAppVisible = true
            context.prepareRecipes()
            context.restoreIfNeeded()
            context.saveOpenRecipe()
        }
        .onDisappear { context.isRecipesAppVisible = false }
        .onChange(of: handoffState, initial: true) { context.updateHandoff() }
        .onChange(of: openRecipeState) { context.saveOpenRecipe() }
        .nightModeAware()
    }

    /// The catalog recipe being previewed, from a search, Discover or the assistant.
    private var previewBinding: Binding<CatalogRecipe?> {
        Binding(get: { context.previewedResult }, set: { context.previewedResult = $0 })
    }

    /// Changes whenever the recipe, cooking step or meal plan week to reopen changes.
    private var openRecipeState: String {
        "\(context.screen)-\(context.session?.recipe.id.uuidString ?? "")-\(context.session?.stepIndex ?? 0)"
            + "-\(context.recipeOrigin)-\(context.mealPlanWeek.start.isoString)"
    }

    /// Changes whenever the recipe offered for Handoff should change.
    private var handoffState: String {
        "\(context.isRecipesAppVisible)-\(context.screen)-\(context.session?.recipe.id.uuidString ?? "")"
    }
}
