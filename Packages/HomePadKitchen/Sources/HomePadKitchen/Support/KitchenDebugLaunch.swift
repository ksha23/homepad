#if DEBUG
import Foundation
import HomePadCore

/// Launch arguments that put the kitchen screens into a known state, for
/// simulator screenshots where nothing can be tapped. Debug builds only.
///
///     -KitchenDemo card            the first recipe's card
///     -KitchenDemo cooking         cooking mode (add -KitchenDemoStep 4 for a step)
///     -KitchenDemo timers          three timers, one paused
///     -KitchenDemo finished        a timer that finishes after two seconds
///     -KitchenDemo search          search results (-KitchenDemoQuery "chicken curry")
///     -KitchenDemo preview         the first result's preview sheet
///     -KitchenDemo saved           the first result saved, its preview showing Saved
///     -KitchenDemo assistant       runs search_recipes and save_recipe as the assistant
///                                  would, and writes the replies to tmp/KitchenAssistantDemo.txt
///     -KitchenDemo mealPlan        this week's meal plan, planned with demo recipes once
///     -KitchenDemo mealPlanGroceries  the same, with the week's merged shopping list open
///     -KitchenDemoCatalog offline  the catalog answers as if HomePad were offline
///     -KitchenDemoNoAlarms YES     turn background alarms off first, so the
///                                  AlarmKit permission prompt does not cover screenshots
///     -KitchenDemoTimers YES       the three timers of `timers` alongside any other mode,
///                                  such as cooking mode with timers running
@MainActor
enum KitchenDebugLaunch {
    /// A catalog that replaces TheMealDB, chosen before the kitchen context exists.
    static func catalog() -> (any RecipeCatalog)? {
        UserDefaults.standard.string(forKey: "KitchenDemoCatalog") == "offline" ? OfflineCatalog() : nil
    }

    static func apply(context: KitchenContext, services: AppServices) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "KitchenDemoNoAlarms") {
            services.settings[KitchenSettings.backgroundAlarms] = false
        }
        if defaults.bool(forKey: "KitchenDemoTimers") { startDemoTimers(services) }
        guard let mode = defaults.string(forKey: "KitchenDemo") else { return }
        let query = defaults.string(forKey: "KitchenDemoQuery") ?? "chicken curry"
        switch mode {
        case "card", "cooking":
            guard let recipe = context.library.recipes.first else { return }
            context.open(recipe)
            if mode == "cooking" {
                context.startCooking()
                context.session?.go(to: max(0, defaults.integer(forKey: "KitchenDemoStep") - 1))
            }
        case "timers":
            startDemoTimers(services)
        case "finished":
            services.timers.start(duration: 2, label: "Soft-boiled eggs")
        case "search", "preview", "saved":
            Task {
                let results = await context.search.run(query)
                guard mode != "search", let first = results.first else { return }
                if mode == "saved" { context.save(first.recipe, open: false) }
                context.preview(first)
            }
        case "assistant":
            Task { await runAssistantDemo(context: context, query: query) }
        case "mealPlan", "mealPlanGroceries":
            planDemoWeek(context)
            context.showMealPlan(.current())
            context.showsMealPlanGroceries = mode == "mealPlanGroceries"
        default:
            break
        }
    }

    /// A week whose meals share ingredients, so the merged list has something
    /// to add up: chili today, tacos and a smoothie tomorrow, the soup for six
    /// the day after, and French toast earlier in the week. Planned once, so
    /// relaunching keeps the same week.
    private static func planDemoWeek(_ context: KitchenContext) {
        let week = MealWeek.current()
        guard context.plannedRecipes(from: week.start, through: week.end()).isEmpty else { return }
        let today = MealDay.today()
        for recipe in DemoRecipes.all where context.library.recipe(recipe.id) == nil {
            context.library.add(recipe)
        }
        func recipe(_ title: String) -> Recipe? { context.library.recipes.first { $0.title == title } }
        let plan: [(title: String, offset: Int, servings: Int?)] = [
            ("Weeknight Chili", 0, nil), ("Chicken Tacos", 1, nil), ("Banana Oat Smoothie", 1, 2),
            ("Butternut Squash Soup", 2, 6),
        ]
        for meal in plan {
            guard let recipe = recipe(meal.title) else { continue }
            context.plan(recipe, on: today.adding(days: meal.offset), servings: meal.servings)
        }
        if week.start < today, let toast = recipe("Brioche French Toast") {
            context.plan(toast, on: week.start)
        }
    }

    /// Pasta and a soup step running, and bread paused.
    private static func startDemoTimers(_ services: AppServices) {
        services.timers.start(duration: 15 * 60, label: "Pasta")
        services.timers.start(duration: 4 * 60 + 30, label: "Step 2 · Butternut Squash Soup")
        let paused = services.timers.start(duration: 40 * 60, label: "Bread")
        services.timers.pause(paused.id)
    }

    /// Calls the registered tools the way the assistant does after "find a
    /// chicken curry recipe" and "save the first one".
    private static func runAssistantDemo(context: KitchenContext, query: String) async {
        let tools = KitchenAssistantTools.make(context: context)
        var transcript = ""
        for (name, arguments) in [("search_recipes", ["query": JSONValue.string(query)]), ("save_recipe", ["number": 1])] {
            guard let tool = tools.first(where: { $0.name == name }) else { continue }
            let reply = (try? await tool.handler(.object(arguments))) ?? "(failed)"
            transcript += "\(name) \(JSONValue.object(arguments).jsonString())\n\(reply)\n\n"
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "KitchenAssistantDemo.txt")
        try? transcript.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Recipes for the demo week, with fixed identifiers so they are added once.
private enum DemoRecipes {
    static let all = [chili, tacos, smoothie]

    static let chili = Recipe(
        id: UUID(uuidString: "6D3A1E2C-0F1B-4C55-9E2A-6A1D2B3C4D01")!, title: "Weeknight Chili", source: "Home Cookbook",
        totalTime: 50 * 60, servings: 6,
        ingredients: ["2 tablespoons olive oil", "1 large yellow onion, diced", "3 garlic cloves, minced", "2 pounds ground beef",
                      "2 tablespoons chili powder", "1 teaspoon ground cumin", "1 (28 oz) can crushed tomatoes",
                      "2 (15 oz) cans kidney beans, drained", "1 cup water", "1 cup shredded cheddar, for serving"],
        sections: [RecipeSection(steps: ["Brown the onion, garlic and beef in the oil.", "Add the rest and simmer for 30 minutes."])])

    static let tacos = Recipe(
        id: UUID(uuidString: "6D3A1E2C-0F1B-4C55-9E2A-6A1D2B3C4D02")!, title: "Chicken Tacos", source: "Home Cookbook",
        totalTime: 30 * 60, servings: 4,
        ingredients: ["1 tablespoon olive oil", "1 pound chicken thighs", "1 small yellow onion, sliced", "2 cloves garlic",
                      "1 teaspoon ground cumin", "8 corn tortillas", "1/2 cup shredded cheddar", "2 limes", "Fresh cilantro"],
        sections: [RecipeSection(steps: ["Cook the chicken with the onion, garlic and cumin.", "Fill the warm tortillas."])])

    static let smoothie = Recipe(
        id: UUID(uuidString: "6D3A1E2C-0F1B-4C55-9E2A-6A1D2B3C4D03")!, title: "Banana Oat Smoothie", source: "Home Cookbook",
        totalTime: 5 * 60, servings: 1,
        ingredients: ["1 banana", "1 cup oat milk", "2 tablespoons rolled oats", "1 teaspoon honey"],
        sections: [RecipeSection(steps: ["Blend everything until smooth."])])
}

/// Answers every request as if the network were down, for the offline screens.
private struct OfflineCatalog: RecipeCatalog {
    let name = "TheMealDB"
    func search(_ query: String) async throws -> [CatalogRecipe] { throw RecipeCatalogError.offline }
    func recipe(id: String) async throws -> CatalogRecipe? { throw RecipeCatalogError.offline }
    func discover(count: Int) async throws -> [CatalogRecipe] { throw RecipeCatalogError.offline }
    func catalogID(for url: URL) -> String? { nil }
}

#endif
