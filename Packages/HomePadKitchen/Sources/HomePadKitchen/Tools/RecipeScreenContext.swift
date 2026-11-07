import HomePadCore

/// What the Recipes app shows, for the assistant: the recipe card, the step in
/// cooking mode or a catalog preview, with the ingredients as they read on
/// screen. "Add these to my shopping list" or "how long does this bake" then
/// needs no recipe name.
@MainActor
enum RecipeScreenContext {
    static func provider(context: KitchenContext) -> ScreenContextProvider {
        ScreenContextProvider(appID: KitchenModule.recipesAppID) { summary(of: context) }
    }

    static func summary(of context: KitchenContext) -> String? {
        if let preview = context.previewedResult {
            let ingredients = preview.recipe.ingredients.joined(separator: "; ")
            return "A preview of \(preview.recipe.title) from the online catalog, not saved yet."
                + (ingredients.isEmpty ? "" : " Ingredients: \(ingredients).")
        }
        if context.screen == .mealPlan { return mealPlan(of: context) }
        guard let session = context.session else { return nil }
        switch context.screen {
        case .cooking:
            return "Cooking mode for \(session.recipe.title). \(session.spokenStep()) \(ingredients(of: session))"
        case .recipe:
            return "The recipe card for \(session.recipe.title). \(ingredients(of: session))"
        case .library, .mealPlan:
            return nil
        }
    }

    /// "The meal plan for this week, November 1 to 7. Thursday, November 5:
    /// Weeknight Chili, for 6." Days with nothing planned are left out.
    private static func mealPlan(of context: KitchenContext) -> String {
        let week = context.mealPlanWeek
        let range = MealPlanFormat.weekRange(week)
        let title = MealPlanFormat.weekTitle(week).map { "\($0.lowercased()), \(range)" } ?? range
        let planned = context.plannedRecipes(from: week.start, through: week.end())
        guard !planned.isEmpty else { return "The meal plan for \(title), with nothing planned yet." }
        let days = Dictionary(grouping: planned, by: \.meal.day).sorted { $0.key < $1.key }.map { day, meals in
            "\(MealPlanFormat.fullDay(day)): " + meals.map { meal in
                meal.meal.servings.map { "\(meal.recipe.title), for \($0)" } ?? meal.recipe.title
            }.joined(separator: "; ") + "."
        }
        return "The meal plan for \(title). " + days.joined(separator: " ")
    }

    /// "Ingredients for 4 servings: 4 eggs; 1 cup milk. Ticked off as on hand: 4 eggs."
    private static func ingredients(of session: RecipeSession) -> String {
        let lines = session.displayIngredients.map(\.text)
        guard !lines.isEmpty else { return "" }
        let heading = session.canScale ? "Ingredients for \(session.servings) servings" : "Ingredients"
        var text = "\(heading): \(lines.joined(separator: "; "))."
        let ticked = lines.indices.filter(session.checkedIngredients.contains).map { lines[$0] }
        if !ticked.isEmpty { text += " Ticked off as on hand: \(ticked.joined(separator: "; "))." }
        return text
    }
}
