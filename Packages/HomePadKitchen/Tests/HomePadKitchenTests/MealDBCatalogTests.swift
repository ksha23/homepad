import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// TheMealDB client and mapper, from fixtures saved from the live API in October 2026.
@Suite struct MealDBCatalogTests {
    private let curryFixtures = [
        "search.php?s=chicken curry": "mealdb-search-chicken-curry",
        "search.php?s=chicken": "mealdb-search-chicken-curry",
        "search.php?s=curry": "mealdb-search-curry",
        "lookup.php?i=52982": "mealdb-lookup-52982",
        "lookup.php?i=52802": "mealdb-lookup-52802",
    ]

    @Test func searchMapsFullRecipes() async throws {
        let fetcher = FixtureCatalogFetcher(curryFixtures)
        let results = try await MealDBCatalog(fetcher: fetcher).search("Find me a chicken curry recipe")
        #expect(fetcher.requests.map(\.absoluteString) == ["https://www.themealdb.com/api/json/v1/1/search.php?s=chicken%20curry"])
        #expect(results.map(\.recipe.title) == ["Katsu Chicken curry", "Nutty Chicken Curry",
                                                 "Bengali Chicken Curry with Potatoes", "Panang chicken curry (kaeng panang gai)"])

        let katsu = try #require(results.first)
        #expect(katsu.id == "mealdb:52820")
        #expect(katsu.kindLine == "Japanese · Chicken")
        #expect(katsu.thumbnailURL?.absoluteString == "https://www.themealdb.com/images/media/meals/vwrpps1503068729.jpg/medium")
        let recipe = katsu.recipe
        #expect(recipe.source == "TheMealDB")
        #expect(recipe.sourceURL?.absoluteString == "https://www.themealdb.com/meal/52820")
        #expect(recipe.imageURL?.absoluteString == "https://www.themealdb.com/images/media/meals/vwrpps1503068729.jpg")
        #expect(recipe.summary == "Adapted from allrecipes.co.uk.")
        #expect(recipe.tags == ["Japanese", "Chicken", "Curry", "Meat"])
        // The "Prep:15min › Cook:30min › Ready in:45min" line becomes times, not a step.
        #expect(recipe.prepTime == 900)
        #expect(recipe.cookTime == 1800)
        #expect(recipe.totalTime == 2700)
        #expect(recipe.steps.count == 6)
        #expect(recipe.steps[0].text.hasPrefix("For the curry sauce: Heat oil"))
        #expect(recipe.ingredients.count == 16)
        #expect(recipe.ingredients[0] == "4 chicken breast, pounded to 1cm thickness")
        #expect(recipe.ingredients[2] == "1 egg, beaten")
        #expect(recipe.ingredients[11] == "600ml chicken stock")
    }

    @Test func stepHeadingsAndNumberingAreRemoved() async throws {
        let catalog = MealDBCatalog(fetcher: FixtureCatalogFetcher(curryFixtures))
        let carbonara = try #require(try await catalog.recipe(id: "mealdb:52982")).recipe
        #expect(carbonara.steps.count == 12)
        #expect(carbonara.steps[0].text == "Put a large saucepan of water on to boil.")
        #expect(!carbonara.steps.contains { $0.text.uppercased().hasPrefix("STEP") })
        #expect(carbonara.ingredients.contains("Salt, as required"))
        // No time fields, so the times in the steps are added up.
        #expect((carbonara.cookTime ?? 0) >= 15 * 60)

        let pie = try #require(try await catalog.recipe(id: "mealdb:52802")).recipe
        #expect(pie.steps.count == 5)
        #expect(pie.steps[0].text.hasPrefix("Put the potatoes"))
        #expect(pie.summary == nil)
        #expect(pie.ingredients.contains("Large handful of Parsley"))
        #expect(pie.ingredients.contains("Juice of 1 Lemon"))
        #expect(pie.ingredients.contains("1 Leek, finely sliced"))
    }

    @Test func wordsOutOfOrderFallBackToEachWord() async throws {
        let fetcher = FixtureCatalogFetcher(curryFixtures)
        let results = try await MealDBCatalog(fetcher: fetcher).search("curry chicken")
        #expect(fetcher.requests.count == 3)
        // Recipes with both words come first.
        let top = try #require(results.first)
        #expect(MealDBCatalog.matchCount(of: ["curry", "chicken"], in: top) == 2)
        #expect(results.contains { $0.recipe.title == "Thai Green Curry" })
        #expect(results.count <= 24)
    }

    @Test func noMatchesIsAnEmptyList() async throws {
        let results = try await MealDBCatalog(fetcher: FixtureCatalogFetcher()).search("zzzz")
        #expect(results.isEmpty)
    }

    @Test func offlineIsReported() async {
        await #expect(throws: RecipeCatalogError.offline) {
            try await MealDBCatalog(fetcher: FixtureCatalogFetcher(isOffline: true)).search("soup")
        }
    }

    @Test func supporterKeyReplacesTheFreeKey() async throws {
        let free = FixtureCatalogFetcher(["random.php?": "mealdb-lookup-52982"])
        let picks = try await MealDBCatalog(fetcher: free).discover(count: 4)
        #expect(free.requests.count == 4)
        #expect(free.requests.allSatisfy { $0.path().hasSuffix("/v1/1/random.php") })
        #expect(picks.map(\.id) == ["mealdb:52982"]) // the same pick four times counts once

        let supporter = FixtureCatalogFetcher(["randomselection.php?": "mealdb-search-curry"])
        let catalog = MealDBCatalog(fetcher: supporter, supporterKey: { " abc123 " })
        let selection = try await catalog.discover(count: 10)
        #expect(supporter.requests.map(\.path) == ["/api/json/v1/abc123/randomselection.php"])
        #expect(selection.count == 10)
    }

    @Test(arguments: [
        ("https://www.themealdb.com/meal/52820", "mealdb:52820"),
        ("https://www.themealdb.com/meal/52820-katsu-chicken-curry", "mealdb:52820"),
        ("https://themealdb.com/meal.php?c=52982", "mealdb:52982"),
        ("https://www.bbcgoodfood.com/recipes/easy-pancakes", nil),
    ])
    func recognizesItsOwnPages(link: String, expected: String?) throws {
        #expect(MealDBCatalog().catalogID(for: try #require(URL(string: link))) == expected)
    }

    @Test func importerReadsCatalogLinksThroughTheAPI() async throws {
        struct NoPages: RecipePageFetching {
            func html(for url: URL) async throws -> String { throw URLError(.badURL) }
        }
        let catalog = MealDBCatalog(fetcher: FixtureCatalogFetcher(curryFixtures))
        let importer = await RecipeImporter(fetcher: NoPages(), catalog: catalog)
        let recipe = try await importer.importRecipe(from: "themealdb.com/meal/52982-spaghetti-alla-carbonara")
        #expect(recipe.title == "Spaghetti alla Carbonara")
    }

    @Test(arguments: [
        ("To taste", "salt", "salt, to taste"),
        ("Pinch", "Salt", "Pinch of Salt"),
        ("1 large", "onion", "1 large onion"),
        ("2 tablespoons", "plain flour", "2 tablespoons plain flour"),
        ("", "Basil", "Basil"),
    ])
    func ingredientLines(measure: String, name: String, expected: String) {
        #expect(MealDBRecipeMapper.ingredientLine(measure: measure, name: name) == expected)
    }
}
