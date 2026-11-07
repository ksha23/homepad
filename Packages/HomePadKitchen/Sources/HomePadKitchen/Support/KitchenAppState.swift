import Foundation
import HomePadCore

/// What the Timers and Recipes apps keep between openings (see `@AppState`).
/// Shared by the household, like the kitchen. Within one launch the Recipes
/// app also keeps everything else about the open recipe in `KitchenContext`.
enum KitchenAppState {
    /// The timer shown in the big ring.
    static let timer = AppStateKey<HomeTimer.ID?>("timers.selected", default: nil)
    /// The recipe whose card or cooking mode is open, so a relaunch reopens it.
    static let openRecipe = AppStateKey<Recipe.ID?>("recipes.open", default: nil)
    /// The step cooking mode was on. A time position: after a few hours or on
    /// another day the recipe reopens on its card instead.
    static let cookingStep = AppStateKey<Int?>("recipes.cookingStep", default: nil, lifetime: .timePosition)
    /// The meal plan was open, or the recipe open was opened from it, so Back
    /// goes there again.
    static let mealPlanOpen = AppStateKey<Bool>("recipes.mealPlanOpen", default: false)
    /// The first day of the week the meal plan showed, when not this week. A
    /// time position: after a few hours or on another day it opens on this week.
    static let mealPlanWeek = AppStateKey<MealDay?>("recipes.mealPlanWeek", default: nil, lifetime: .timePosition)
}
