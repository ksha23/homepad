import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// The assistant's recipe tools, called the way the assistant calls them: by
/// name from the registered list, with JSON arguments, against fixtures.
@MainActor
@Suite struct RecipeCatalogToolsTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kitchen-tools-\(UUID().uuidString)")

    private struct FixturePage: RecipePageFetching {
        func html(for url: URL) async throws -> String {
            guard url.host() == "recipes.example" else { throw URLError(.cannotFindHost) }
            let file = try #require(Bundle.module.url(forResource: "nyt-style", withExtension: "html", subdirectory: "Fixtures"))
            return try String(contentsOf: file, encoding: .utf8)
        }
    }

    private func makeContext(_ catalog: any RecipeCatalog) -> KitchenContext {
        KitchenContext(services: nil, library: RecipeLibrary(directory: directory),
                       importer: RecipeImporter(fetcher: FixturePage(), catalog: catalog), catalog: catalog)
    }

    private func call(_ name: String, _ arguments: JSONValue = [:], in context: KitchenContext) async throws -> String {
        let tool = try #require(KitchenAssistantTools.make(context: context).first { $0.name == name })
        return try await tool.handler(arguments)
    }

    private var curryCatalog: MealDBCatalog {
        MealDBCatalog(fetcher: FixtureCatalogFetcher(["search.php?s=chicken curry": "mealdb-search-chicken-curry"]))
    }

    @Test func toolsAreRegisteredWithRequiredArguments() throws {
        let tools = KitchenAssistantTools.make(context: makeContext(curryCatalog))
        for name in ["search_recipes", "preview_recipe", "save_recipe", "import_recipe_link"] {
            #expect(tools.contains { $0.name == name })
        }
        let search = try #require(tools.first { $0.name == "search_recipes" })
        #expect(search.parameters["required"] == ["query"])
        #expect(search.description.contains("recipe"))
    }

    @Test func searchListsNumberedResultsAndShowsThem() async throws {
        let context = makeContext(curryCatalog)
        let reply = try await call("search_recipes", ["query": "chicken curry"], in: context)
        #expect(reply.hasPrefix("Found 4 on TheMealDB"))
        #expect(reply.contains("1. Katsu Chicken curry (Japanese · Chicken, 45 min, 16 ingredients)."))
        #expect(reply.contains("4. Panang chicken curry"))
        #expect(reply.contains("save_recipe only after"))
        #expect(context.search.query == "chicken curry")
        #expect(context.search.results.count == 4)
        #expect(context.screen == .library)
    }

    @Test func saveByNumberGoesIntoTheLibraryOnce() async throws {
        let context = makeContext(curryCatalog)
        _ = try await call("search_recipes", ["query": "chicken curry"], in: context)
        let before = context.library.recipes.count

        let reply = try await call("save_recipe", ["number": 2], in: context)
        #expect(reply == "Saved Nutty Chicken Curry to My Recipes and opened it. It has 9 ingredients and \(context.session?.steps.count ?? 0) steps.")
        #expect(context.library.recipes.count == before + 1)
        #expect(context.session?.recipe.title == "Nutty Chicken Curry")
        #expect(context.screen == .recipe)

        let again = try await call("save_recipe", ["name": "nutty chicken curry"], in: context)
        #expect(again == "Nutty Chicken Curry is already in My Recipes, so it is open now.")
        #expect(context.library.recipes.count == before + 1)
    }

    @Test func previewShowsWithoutSavingAndSaveUsesIt() async throws {
        let context = makeContext(curryCatalog)
        _ = try await call("search_recipes", ["query": "chicken curry"], in: context)
        let reply = try await call("preview_recipe", ["name": "panang"], in: context)
        #expect(reply.hasPrefix("Showing Panang chicken curry"))
        #expect(reply.contains("Ingredients: 400ml Coconut Milk"))
        #expect(context.previewedResult?.recipe.title == "Panang chicken curry (kaeng panang gai)")
        #expect(context.savedRecipe(for: try #require(context.previewedResult)) == nil)

        // "Save that one" with no number saves the recipe on screen.
        let saved = try await call("save_recipe", in: context)
        #expect(saved.hasPrefix("Saved Panang chicken curry"))
        #expect(context.previewedResult == nil)
    }

    @Test func unclearChoicesAskInsteadOfGuessing() async throws {
        let context = makeContext(curryCatalog)
        #expect(try await call("save_recipe", ["number": 1], in: context) == "There are no search results yet. Call search_recipes first.")
        _ = try await call("search_recipes", ["query": "chicken curry"], in: context)
        #expect(try await call("save_recipe", in: context) == "Say which result: a number from 1 to 4, or its name.")
        #expect(try await call("save_recipe", ["number": 9], in: context) == "Say which result: a number from 1 to 4, or its name.")
    }

    @Test func searchReportsNoResultsAndOffline() async throws {
        let empty = makeContext(MealDBCatalog(fetcher: FixtureCatalogFetcher()))
        let none = try await call("search_recipes", ["query": "unicorn stew"], in: empty)
        #expect(none.hasPrefix("TheMealDB has no recipes for \"unicorn stew\"."))

        let offline = makeContext(MealDBCatalog(fetcher: FixtureCatalogFetcher(isOffline: true)))
        let reply = try await call("search_recipes", ["query": "soup"], in: offline)
        #expect(reply == RecipeCatalogError.offline.localizedDescription)
    }

    @Test func importLinkSavesThePage() async throws {
        let context = makeContext(curryCatalog)
        let reply = try await call("import_recipe_link", ["url": "https://recipes.example/soup"], in: context)
        let recipe = try #require(context.session?.recipe)
        #expect(reply.hasPrefix("Added \(recipe.title)"))
        #expect(context.library.recipe(withSource: URL(string: "https://recipes.example/soup")) != nil)

        let failed = try await call("import_recipe_link", ["url": "not a link"], in: context)
        #expect(failed == RecipeImportError.invalidURL.localizedDescription)
    }
}
