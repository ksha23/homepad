import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

extension StubCatalog {
    /// Every starter recipe, as the real catalog would answer.
    @MainActor
    static func starterCatalog() -> StubCatalog {
        StubCatalog(recipes: RecipeStarterSet.catalogIDs.map { id in sample(Int(id.dropFirst("mealdb:".count)) ?? 0) })
    }
}

/// The starter set, deleted-recipe memory, Discover and the search model.
@MainActor
@Suite struct RecipeAutoFillTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kitchen-autofill-\(UUID().uuidString)")

    @Test func starterSetFillsANewLibraryOnce() async {
        let library = RecipeLibrary(directory: directory)
        let catalog = StubCatalog.starterCatalog()
        let added = await RecipeStarterSet.add(to: library, from: catalog)
        #expect(added == RecipeStarterSet.catalogIDs.count)
        #expect(library.recipes.count == RecipeStarterSet.catalogIDs.count + 2) // plus the bundled samples
        #expect(library.hasStarterSet)
        // Newest first keeps the curated order.
        let starter = library.recipes.filter { $0.source == "TheMealDB" }.map(\.title)
        #expect(starter.first == "Recipe 52770")

        let again = await RecipeStarterSet.add(to: library, from: catalog)
        #expect(again == 0)
        #expect(RecipeLibrary(directory: directory).hasStarterSet)
    }

    @Test func deletedRecipesAreNotAddedBack() async throws {
        let library = RecipeLibrary(directory: directory)
        let bolognese = try #require(StubCatalog.sample(52770).recipe.sourceURL)
        library.add(StubCatalog.sample(52770).recipe)
        library.delete(try #require(library.recipe(withSource: bolognese)).id)

        // Deletions survive a relaunch.
        let relaunched = RecipeLibrary(directory: directory)
        #expect(relaunched.wasDeleted(source: bolognese))
        await RecipeStarterSet.add(to: relaunched, from: StubCatalog.starterCatalog())
        #expect(relaunched.recipe(withSource: bolognese) == nil)
        #expect(relaunched.recipes.count == RecipeStarterSet.catalogIDs.count - 1 + 2)

        // Saving it on purpose brings it back and forgets the deletion.
        relaunched.add(StubCatalog.sample(52770).recipe)
        #expect(!relaunched.wasDeleted(source: bolognese))
    }

    @Test func offlineFirstLaunchTriesAgainLater() async {
        let library = RecipeLibrary(directory: directory)
        let catalog = StubCatalog.starterCatalog()
        catalog.isOffline = true
        #expect(await RecipeStarterSet.add(to: library, from: catalog) == 0)
        #expect(!library.hasStarterSet)
        #expect(library.recipes.count == 2)

        catalog.isOffline = false
        #expect(await RecipeStarterSet.add(to: library, from: catalog) == RecipeStarterSet.catalogIDs.count)
    }

    @Test func discoverKeepsPicksForAWhileAndSurvivesFailures() async {
        let catalog = StubCatalog(searchResults: (1...12).map { StubCatalog.sample($0) })
        let discovery = RecipeDiscovery(catalog: catalog)
        let now = Date()
        await discovery.refreshIfStale(now: now)
        #expect(discovery.picks.count == RecipeDiscovery.count)

        catalog.isOffline = true
        await discovery.refreshIfStale(now: now.addingTimeInterval(60))
        #expect(discovery.failure == nil) // still fresh, nothing fetched
        await discovery.refresh(now: now.addingTimeInterval(60))
        #expect(discovery.failure == .offline)
        #expect(discovery.picks.count == RecipeDiscovery.count) // the old picks stay
    }

    @Test func searchPhases() async {
        let catalog = StubCatalog(searchResults: [StubCatalog.sample(1, title: "Pad Thai")])
        let search = RecipeSearch(catalog: catalog, typingPause: .zero)
        #expect(!search.isActive)

        let found = await search.run("  pad thai ")
        #expect(search.query == "pad thai")
        #expect(found.map(\.recipe.title) == ["Pad Thai"])
        #expect(search.phase == .results(found))

        catalog.isOffline = true
        await search.run("noodles")
        #expect(search.phase == .failed(message: RecipeCatalogError.offline.localizedDescription, isOffline: true))
        #expect(search.results.isEmpty)

        search.update(query: "pa")
        #expect(search.isActive)
        #expect(search.phase == .idle) // waits for a third letter
        search.clear()
        #expect(!search.isActive)
    }

    @Test func everyEntryPointSavesTheSameWay() async throws {
        let catalog = StubCatalog(recipes: [StubCatalog.sample(7)])
        let library = RecipeLibrary(directory: directory)
        let context = KitchenContext(services: nil, library: library, catalog: catalog)
        let viaLink = try #require(await context.importRecipe(link: "https://www.themealdb.com/meal/7"))
        #expect(context.importStatus == .imported("Recipe 7"))
        #expect(context.screen == .recipe)

        // Saving the same catalog recipe again replaces it instead of adding a copy.
        let viaSearch = context.save(StubCatalog.sample(7).recipe, open: false)
        #expect(viaSearch.id == viaLink.id)
        #expect(library.recipes.filter { $0.sourceURL == viaLink.sourceURL }.count == 1)
        #expect(context.savedRecipe(for: StubCatalog.sample(7))?.id == viaLink.id)
    }
}
