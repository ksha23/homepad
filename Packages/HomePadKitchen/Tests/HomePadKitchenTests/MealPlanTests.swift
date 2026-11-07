import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// The meal plan: planned recipes merged into one shopping list, what the
/// Groceries list already has, the plan's days and saving, and the
/// assistant's plan tools.
@MainActor
@Suite struct MealPlanTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kitchen-mealplan-\(UUID().uuidString)")
    let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "test.kitchen.mealplan.\(UUID())")!))
    let groceries = GroceryListCalendar()

    static let soup = Recipe(title: "Roasted Squash Soup", servings: 4, ingredients: [
        "2 tablespoons olive oil", "1 medium yellow onion, chopped", "2 cloves garlic, minced",
        "1 butternut squash (about 3 lb), peeled and cubed", "4 cups vegetable broth", "1 teaspoon kosher salt",
        "1/2 cup heavy cream", "6 fresh sage leaves, for garnish", "Salt, to taste",
    ], sections: [RecipeSection(steps: ["Simmer everything."])])

    static let chili = Recipe(title: "Chili", servings: 6, ingredients: [
        "1/4 cup olive oil", "2 yellow onions, diced", "3 garlic cloves", "2 pounds ground beef",
        "1 (15 oz) can kidney beans, drained", "2 (15 oz) cans kidney beans", "1 (28 oz) can crushed tomatoes",
        "2 cups water", "Salt", "1 cup shredded cheddar, for serving",
    ], sections: [RecipeSection(steps: ["Simmer everything."])])

    /// No servings, like TheMealDB's recipes, so it is shopped for as written.
    static let pancakes = Recipe(title: "Pancakes", ingredients: [
        "For the batter:", "1 cup milk", "250 ml milk", "2 cups flour", "200 g flour", "2 large eggs", "1 egg",
        "2-3 tablespoons sugar", "1 tablespoon sugar", "Fresh berries, for serving", "1 cup blueberries",
    ], sections: [RecipeSection(steps: ["Whisk and fry."])])

    /// Thursday, November 5, 2026.
    let thursday = MealDay(year: 2026, month: 11, day: 5)

    private func makeContext() -> KitchenContext {
        services.calendar = groceries
        return KitchenContext(services: services, library: RecipeLibrary(directory: directory))
    }

    private func texts(_ items: [GroceryItem]) -> [String] { items.map(\.text) }

    // MARK: Merging

    @Test func theSameIngredientAddsUpAcrossRecipesScaledToTheirServings() {
        let items = GroceryMerger.merge([MealServing(recipe: Self.soup, servings: 8), MealServing(recipe: Self.chili, servings: 6)])
        #expect(texts(items) == [
            "½ cup olive oil", "4 yellow onions", "7 cloves garlic", "2 butternut squashes", "8 cups vegetable broth",
            "2 teaspoons kosher salt", "1 cup heavy cream", "12 sage leaves", "Salt", "2 pounds ground beef",
            "3 (15 oz) cans kidney beans", "1 (28 oz) can crushed tomatoes", "1 cup cheddar",
        ])
        // Four tablespoons of soup oil and a quarter cup of chili oil.
        #expect(items.first { $0.key == "olive oil" }?.recipes == ["Roasted Squash Soup", "Chili"])
        #expect(!items.contains { $0.key == "water" })
    }

    @Test func countsThatAreBoughtWholeRoundUp() {
        let items = GroceryMerger.merge([MealServing(recipe: Self.soup, servings: 4), MealServing(recipe: Self.chili, servings: 3)])
        let text = texts(items)
        #expect(text.contains("¼ cup olive oil"))
        #expect(text.contains("2 yellow onions"))
        // 2 cloves and half of 3: nobody buys half a clove or half a can.
        #expect(text.contains("4 cloves garlic"))
        #expect(text.contains("2 (15 oz) cans kidney beans"))
        #expect(text.contains("1 (28 oz) can crushed tomatoes"))
    }

    @Test func unitsConvertWhereTheyCanAndStandSideBySideWhereTheyCannot() {
        let asWritten = texts(GroceryMerger.merge([MealServing(recipe: Self.pancakes, servings: nil)]))
        #expect(asWritten == ["2 cups milk", "2 cups and 200 g flour", "3 eggs", "3–4 tablespoons sugar", "Berries", "1 cup blueberries"])
        let metric = texts(GroceryMerger.merge([MealServing(recipe: Self.pancakes, servings: nil)], system: .metric))
        #expect(metric.first == "485 ml milk")
    }

    @Test func listItemsMatchMergedItemsByName() {
        #expect(GroceryMerger.key(forListItem: "Eggs") == "egg")
        #expect(GroceryMerger.key(forListItem: "3 yellow onions") == "yellow onion")
        #expect(GroceryMerger.key(forListItem: "5 cloves garlic") == "garlic")
        #expect(GroceryMerger.key(forListItem: "Oat milk") == "oat milk")
    }

    // MARK: The Groceries list

    @Test func itemsTheListAlreadyHasAreSetApartAndNotAddedAgain() async throws {
        let context = makeContext()
        let soup = context.library.add(Self.soup)
        groceries.open = ["2 yellow onions", "Bananas"]
        groceries.done = ["Heavy cream"]
        context.plan(soup, on: thursday, servings: 4)

        let list = await context.groceries(for: context.plannedRecipes(on: thursday))
        #expect(list.onList.map(\.key) == ["yellow onion"])
        // Checked off already, so it is to buy again.
        #expect(list.toAdd.contains { $0.key == "heavy cream" })
        #expect(list.mealCount == 1)

        try await context.addToGroceries(list.toAdd.map(\.text))
        #expect(groceries.added.count == list.toAdd.count)
        #expect(groceries.added.allSatisfy { $0.listName == "Groceries" })
        #expect(!groceries.added.contains { $0.title.contains("onion") })
    }

    // MARK: The plan

    @Test func thePlanIsSavedAndLosesRecipesThatAreDeleted() throws {
        let context = makeContext()
        let soup = context.library.add(Self.soup)
        let chili = context.library.add(Self.chili)
        context.plan(soup, on: thursday)
        let chiliMeal = context.plan(chili, on: thursday, servings: 3)

        let reopened = MealPlanStore(directory: directory)
        #expect(reopened.meals == context.mealPlan.meals)
        #expect(context.plannedRecipes(on: thursday).map(\.recipe.title) == ["Roasted Squash Soup", "Chili"])
        // Planned at the recipe's own servings, or as asked.
        #expect(context.plannedRecipes(on: thursday).map(\.meal.servings) == [4, 3])

        context.move(chiliMeal, to: thursday.adding(days: 1))
        #expect(context.plannedRecipes(on: thursday.adding(days: 1)).map(\.recipe.title) == ["Chili"])
        context.deleteRecipe(soup.id)
        #expect(context.mealPlan.meals.map(\.recipeID) == [chili.id])
    }

    @Test func shoppingCoversThisWeekFromTodayOn() {
        let context = makeContext()
        let soup = context.library.add(Self.soup)
        let week = MealWeek(containing: thursday)
        context.plan(soup, on: thursday.adding(days: -1))
        context.plan(soup, on: thursday.adding(days: 1))
        let meals = context.shoppableMeals(in: week, today: thursday)
        #expect(meals.map(\.meal.day) == [thursday.adding(days: 1)])
        #expect(context.shoppableMeals(in: week.offset(by: -1), today: thursday).isEmpty)
    }

    @Test func spokenDaysMeanTheNextOneFromToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let day = { (spoken: String) in MealPlanFormat.day(from: spoken, today: thursday, calendar: calendar) }
        #expect(day("Friday") == MealDay(year: 2026, month: 11, day: 6))
        #expect(day("thursday") == thursday)
        #expect(day("next thursday") == MealDay(year: 2026, month: 11, day: 12))
        #expect(day("tomorrow") == MealDay(year: 2026, month: 11, day: 6))
        #expect(day("2026-11-20") == MealDay(year: 2026, month: 11, day: 20))
        #expect(day("someday") == nil)
    }

    // MARK: The assistant

    private func call(_ name: String, _ arguments: JSONValue, in context: KitchenContext) async throws -> String {
        let tools = MealPlanTools.make(context: context, today: { thursday })
        let tool = try #require(tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    @Test func theAssistantPlansReadsAndClearsADay() async throws {
        let context = makeContext()
        context.library.add(Self.soup)

        let planned = try await call("plan_meal", ["recipe": "roasted squash soup", "day": "Saturday", "servings": 6], in: context)
        #expect(planned == "Planned Roasted Squash Soup for Saturday, November 7, for 6.")
        #expect(context.screen == .mealPlan)
        #expect(context.mealPlanWeek.contains(MealDay(year: 2026, month: 11, day: 7)))

        let read = try await call("get_meal_plan", ["day": "saturday"], in: context)
        #expect(read == "Saturday, November 7: Roasted Squash Soup, for 6.")
        let unknown = try await call("plan_meal", ["recipe": "lasagna", "day": "friday"], in: context)
        #expect(unknown.hasPrefix("No saved recipe matches \"lasagna\"."))

        // The soup for 6 instead of 4: every ingredient once, half as much again.
        let shopped = try await call("add_meal_plan_to_groceries", [:], in: context)
        #expect(shopped == "Added 9 items to Groceries for 1 meal, Saturday.")
        #expect(groceries.added.contains { $0.title == "6 cups vegetable broth" })
        #expect(groceries.added.contains { $0.title == "2 yellow onions" })

        let removed = try await call("remove_planned_meal", ["day": "saturday", "recipe": "soup"], in: context)
        #expect(removed == "Took Roasted Squash Soup off Saturday, November 7.")
        #expect(context.mealPlan.meals.isEmpty)
    }
}

/// A calendar service with a Groceries list, recording what is added to it.
@MainActor
final class GroceryListCalendar: CalendarService {
    var open: [String] = []
    var done: [String] = []
    private(set) var added: [(title: String, listName: String?)] = []

    var hasAccess: Bool { true }
    func requestAccess() async -> Bool { true }
    func events(from start: Date, to end: Date) async -> [CalendarItem] { [] }
    func addEvent(title: String, start: Date, end: Date) async throws {}

    func reminderLists() async -> [ReminderListInfo] {
        [ReminderListInfo(id: "list.groceries", title: "Groceries", isShared: true), ReminderListInfo(id: "list.errands", title: "Errands")]
    }

    func reminders(includeCompleted: Bool) async -> [CalendarItem] {
        func item(_ title: String, completed: Bool) -> CalendarItem {
            CalendarItem(id: title, title: title, start: .distantFuture, end: .distantFuture, isReminder: true,
                         isCompleted: completed, listID: "list.groceries")
        }
        let errand = CalendarItem(id: "errand", title: "Salt", start: .distantFuture, end: .distantFuture, isReminder: true, listID: "list.errands")
        return open.map { item($0, completed: false) } + (includeCompleted ? done.map { item($0, completed: true) } : []) + [errand]
    }

    func addReminder(title: String, due: Date?, listName: String?) async throws {
        added.append((title, listName))
    }
}
