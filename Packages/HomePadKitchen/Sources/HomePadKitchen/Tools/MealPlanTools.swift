import Foundation
import HomePadCore

/// Assistant tools for the meal plan: "what's for dinner Thursday", "put chili
/// on Friday", "take the chili off Friday" and "add this week's meals to the
/// shopping list". The plan belongs to the household like the recipes it
/// holds, so no tool needs a recognized member.
@MainActor
enum MealPlanTools {
    /// - Parameter today: The day "today" and weekdays count from. Tests fix it.
    static func make(context: KitchenContext, today: @escaping () -> MealDay = { .today() }) -> [AssistantTool] {
        [getMealPlan(context, today), planMeal(context, today), removePlannedMeal(context, today), addPlanToGroceries(context, today)]
    }

    private static let dayParameter = Schema.string(
        "A day: an ISO 8601 date such as 2026-11-12, today, tomorrow, or a weekday name, which means the next one from today on.")
    private static let unreadableDay = "I could not tell which day. Use a weekday, today, tomorrow or an ISO 8601 date."

    static func getMealPlan(_ context: KitchenContext, _ today: @escaping () -> MealDay) -> AssistantTool {
        AssistantTool(
            name: "get_meal_plan",
            description: """
            What is planned to eat, for example "what's for dinner Thursday" or "what's on the meal plan this week". \
            The plan puts recipes on days, without breakfast, lunch or dinner.
            """,
            parameters: Schema.object([
                "day": dayParameter,
                "days": Schema.integer("How many days from that day, 1 to 14. Defaults to 1."),
            ])
        ) { arguments in
            let now = today()
            guard let first = day(arguments, now) else { return unreadableDay }
            let count = min(14, max(1, arguments["days"]?.intValue ?? 1))
            let last = first.adding(days: count - 1)
            let planned = context.plannedRecipes(from: first, through: last)
            guard !planned.isEmpty else {
                let when = count == 1 ? "for \(MealPlanFormat.fullDay(first))" : "from \(MealPlanFormat.fullDay(first)) to \(MealPlanFormat.fullDay(last))"
                return "Nothing is planned \(when)."
            }
            let days = Dictionary(grouping: planned, by: \.meal.day).sorted { $0.key < $1.key }
            return days.map { day, meals in
                "\(MealPlanFormat.fullDay(day)): " + meals.map(describe).joined(separator: "; ") + "."
            }.joined(separator: " ")
        }
    }

    static func planMeal(_ context: KitchenContext, _ today: @escaping () -> MealDay) -> AssistantTool {
        AssistantTool(
            name: "plan_meal",
            description: """
            Put a saved recipe on a day of the meal plan, for example "put chili on Friday", and show the plan. \
            The recipe must be in My Recipes. To plan a new one, find it with search_recipes and save it with save_recipe first.
            """,
            parameters: Schema.object([
                "recipe": Schema.string("The saved recipe's name, for example \"chili\"."),
                "day": dayParameter,
                "servings": Schema.integer("How many to cook for, 1 to 48. Optional."),
            ], required: ["recipe", "day"])
        ) { arguments in
            let name = arguments["recipe"]?.stringValue ?? ""
            guard let recipe = context.library.find(named: name) else { return notSaved(name, in: context) }
            guard let day = day(arguments, today()) else { return unreadableDay }
            let servings = arguments["servings"]?.intValue
            if let servings, !(1...48).contains(servings) { return "Servings must be a whole number from 1 to 48." }
            let meal = context.plan(recipe, on: day, servings: servings)
            context.showMealPlan(MealWeek(containing: day), bringToFront: true)
            guard let planned = meal.servings else {
                return "Planned \(recipe.title) for \(MealPlanFormat.fullDay(day)). It does not say how many it serves, so it is cooked as written."
            }
            return "Planned \(recipe.title) for \(MealPlanFormat.fullDay(day)), for \(planned)."
        }
    }

    static func removePlannedMeal(_ context: KitchenContext, _ today: @escaping () -> MealDay) -> AssistantTool {
        AssistantTool(
            name: "remove_planned_meal",
            description: "Take a recipe off a day of the meal plan, for example \"take the chili off Friday\", or clear the day when no recipe is named.",
            parameters: Schema.object([
                "day": dayParameter,
                "recipe": Schema.string("The recipe's name. Optional: without it every meal on that day comes off."),
            ], required: ["day"])
        ) { arguments in
            guard let day = day(arguments, today()) else { return unreadableDay }
            let onDay = context.plannedRecipes(on: day)
            let name = arguments["recipe"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
            let matches = name.isEmpty ? onDay : onDay.filter { matchesName($0.recipe, name) }
            guard !matches.isEmpty else {
                return name.isEmpty
                    ? "Nothing is planned for \(MealPlanFormat.fullDay(day))."
                    : "Nothing called \(name) is planned for \(MealPlanFormat.fullDay(day))."
            }
            matches.forEach { context.mealPlan.remove($0.meal.id) }
            return "Took \(matches.map(\.recipe.title).joined(separator: " and ")) off \(MealPlanFormat.fullDay(day))."
        }
    }

    static func addPlanToGroceries(_ context: KitchenContext, _ today: @escaping () -> MealDay) -> AssistantTool {
        AssistantTool(
            name: "add_meal_plan_to_groceries",
            description: """
            Add the planned meals' ingredients to the Groceries list, for example "add this week's meals to the shopping list". \
            Each recipe is scaled to its planned servings, the same ingredient is added up, and what the list already has is left out. \
            Covers the week of the given day from today on, this week by default.
            """,
            parameters: Schema.object(["day": Schema.string("Any day in the week to shop for, such as next monday. Defaults to today.")])
        ) { arguments in
            let now = today()
            guard let anyDay = day(arguments, now) else { return unreadableDay }
            let week = MealWeek(containing: anyDay)
            let meals = context.shoppableMeals(in: week, today: now)
            guard !meals.isEmpty else {
                return "Nothing is planned from \(MealPlanFormat.fullDay(max(week.start, now))) to \(MealPlanFormat.fullDay(week.end()))."
            }
            let groceries = await context.groceries(for: meals)
            let added = try await context.addToGroceries(groceries.toAdd.map(\.text))
            let mealCount = meals.count == 1 ? "1 meal" : "\(meals.count) meals"
            var reply = "Added \(added) \(added == 1 ? "item" : "items") to Groceries for \(mealCount)"
            if let days = groceries.days { reply += ", \(MealPlanFormat.days(days, today: now))" }
            reply += "."
            if !groceries.onList.isEmpty {
                reply += " Already on the list: \(groceries.onList.map(\.name).joined(separator: ", "))."
            }
            return reply
        }
    }

    // MARK: Helpers

    /// The day argument, or today when there is none.
    private static func day(_ arguments: JSONValue, _ today: MealDay) -> MealDay? {
        guard let spoken = arguments["day"]?.stringValue, !spoken.trimmingCharacters(in: .whitespaces).isEmpty else { return today }
        return MealPlanFormat.day(from: spoken, today: today)
    }

    /// "Chili, for 6", or the title alone for a recipe cooked as written.
    private static func describe(_ planned: PlannedRecipe) -> String {
        planned.meal.servings.map { "\(planned.recipe.title), for \($0)" } ?? planned.recipe.title
    }

    private static func matchesName(_ recipe: Recipe, _ name: String) -> Bool {
        let title = recipe.title.lowercased()
        let needle = name.lowercased()
        return title.contains(needle) || needle.contains(title)
    }

    private static func notSaved(_ name: String, in context: KitchenContext) -> String {
        let titles = context.library.recipes.prefix(12).map(\.title).joined(separator: ", ")
        return "No saved recipe matches \"\(name)\". Saved recipes: \(titles). To plan a new one, use search_recipes and save_recipe first."
    }
}
