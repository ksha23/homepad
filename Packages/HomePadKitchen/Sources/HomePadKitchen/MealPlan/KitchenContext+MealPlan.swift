import Foundation
import HomePadCore

/// A planned meal with its recipe, for views and the assistant.
public struct PlannedRecipe: Identifiable, Hashable, Sendable {
    public let meal: PlannedMeal
    public let recipe: Recipe
    public var id: PlannedMeal.ID { meal.id }

    /// "Serves 6", or nil for a recipe cooked as written.
    public var servingsText: String? {
        meal.servings.map { "Serves \($0)" }
    }
}

/// A week's merged shopping list, split by what the Groceries list already has.
public struct MealPlanGroceries: Equatable, Sendable {
    /// Items to add.
    public var toAdd: [GroceryItem]
    /// Items whose name is already on the list and still to buy, so they are not added twice.
    public var onList: [GroceryItem]
    /// The days the meals are on, first and last.
    public var days: ClosedRange<MealDay>?
    /// How many planned meals went into it.
    public var mealCount: Int

    public static let empty = MealPlanGroceries(toAdd: [], onList: [], days: nil, mealCount: 0)
}

extension KitchenContext {
    // MARK: Planning

    /// Servings a newly planned recipe starts with: the default servings
    /// setting, else the recipe's own. A recipe that does not say how many it
    /// serves is cooked as written.
    func defaultPlannedServings(for recipe: Recipe) -> Int? {
        guard let own = recipe.servings, own > 0 else { return nil }
        let preferred = services?.settings[KitchenSettings.defaultServings] ?? 0
        return preferred > 0 ? preferred : own
    }

    /// Puts a saved recipe on a day.
    @discardableResult
    public func plan(_ recipe: Recipe, on day: MealDay, servings: Int? = nil) -> PlannedMeal {
        let planned = (recipe.servings ?? 0) > 0 ? (servings ?? defaultPlannedServings(for: recipe)) : nil
        return mealPlan.add(recipeID: recipe.id, on: day, servings: planned)
    }

    /// The meals on a day whose recipes are still saved, in planned order.
    public func plannedRecipes(on day: MealDay) -> [PlannedRecipe] {
        withRecipes(mealPlan.meals(on: day))
    }

    /// The meals from one day through another, by day.
    public func plannedRecipes(from first: MealDay, through last: MealDay) -> [PlannedRecipe] {
        withRecipes(mealPlan.meals(from: first, through: last))
    }

    /// Moves a meal to another day.
    public func move(_ meal: PlannedMeal, to day: MealDay) {
        var moved = meal
        moved.day = day
        mealPlan.update(moved)
    }

    /// Changes how many a meal is cooked for.
    public func setServings(_ servings: Int, for meal: PlannedMeal) {
        var changed = meal
        changed.servings = servings
        mealPlan.update(changed)
    }

    /// Deletes a recipe from the library and takes it off the plan.
    public func deleteRecipe(_ id: Recipe.ID) {
        library.delete(id)
        mealPlan.removeAll { $0.recipeID == id }
    }

    /// Opens a planned meal's recipe at its planned servings, with Back to the plan.
    public func open(_ planned: PlannedRecipe) {
        open(planned.recipe, servings: planned.meal.servings, from: .mealPlan)
    }

    private func withRecipes(_ meals: [PlannedMeal]) -> [PlannedRecipe] {
        meals.compactMap { meal in library.recipe(meal.recipeID).map { PlannedRecipe(meal: meal, recipe: $0) } }
    }

    // MARK: Groceries

    /// The meals worth shopping for in a week: today on for this week, every
    /// day for a week ahead, nothing for a week gone by.
    public func shoppableMeals(in week: MealWeek, today: MealDay = .today()) -> [PlannedRecipe] {
        let first = max(week.start, today)
        let last = week.end()
        guard first <= last else { return [] }
        return plannedRecipes(from: first, through: last)
    }

    /// Every planned recipe's ingredients, scaled to its servings and merged,
    /// with what the Groceries list already has set apart.
    public func groceries(for meals: [PlannedRecipe]) async -> MealPlanGroceries {
        guard !meals.isEmpty else { return .empty }
        let system = services?.settings[KitchenSettings.unitSystem] ?? .original
        let merged = GroceryMerger.merge(meals.map { MealServing(recipe: $0.recipe, servings: $0.meal.servings) }, system: system)
        let onList = await openGroceryKeys()
        let days = meals.map(\.meal.day)
        return MealPlanGroceries(
            toAdd: merged.filter { !onList.contains($0.key) },
            onList: merged.filter { onList.contains($0.key) },
            days: days.min().flatMap { first in days.max().map { first...$0 } },
            mealCount: meals.count
        )
    }
}
