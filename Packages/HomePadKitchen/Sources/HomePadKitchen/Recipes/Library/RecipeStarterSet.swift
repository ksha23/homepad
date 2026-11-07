import Foundation
import HomePadCore

/// Ten everyday recipes a new library starts with, fetched from the catalog in
/// the background on first launch: weeknight pasta and fish, a soup, eggs,
/// pancakes, noodles, burgers and a stew. Recipes someone deleted are skipped,
/// and the set is added once. An offline first launch tries again next time.
@MainActor
enum RecipeStarterSet {
    static let catalogIDs = [
        "mealdb:52770", // Spaghetti Bolognese
        "mealdb:52982", // Spaghetti alla Carbonara
        "mealdb:52773", // Honey Teriyaki Salmon
        "mealdb:52963", // Shakshuka
        "mealdb:52854", // Pancakes
        "mealdb:52903", // French Onion Soup
        "mealdb:53191", // Pad Thai
        "mealdb:53085", // 15-minute chicken & halloumi burgers
        "mealdb:52940", // Brown Stew Chicken
        "mealdb:52844", // Lasagne
    ]

    private static let log = Log.make("Kitchen.Starter")

    /// Adds the starter recipes the library lacks. Returns how many were added.
    @discardableResult
    static func add(to library: RecipeLibrary, from catalog: any RecipeCatalog, now: Date = Date()) async -> Int {
        guard !library.hasStarterSet else { return 0 }
        let fetched = await withTaskGroup(of: (Int, CatalogRecipe?)?.self) { group in
            for (index, id) in catalogIDs.enumerated() {
                group.addTask {
                    do { return (index, try await catalog.recipe(id: id)) } catch { return nil }
                }
            }
            return await group.reduce(into: [Int: CatalogRecipe?]()) { found, pair in
                if let pair { found.updateValue(pair.1, forKey: pair.0) }
            }
        }
        // A recipe the catalog no longer has counts as done. A failed request does not.
        guard fetched.count == catalogIDs.count, !library.hasStarterSet else {
            log.info("Starter recipes incomplete (\(fetched.count) of \(catalogIDs.count)), trying again later")
            return 0
        }
        var added = 0
        for index in catalogIDs.indices {
            guard var recipe = fetched[index]??.recipe, let url = recipe.sourceURL,
                  !library.wasDeleted(source: url), library.recipe(withSource: url) == nil else { continue }
            // Newest first in the library, so stagger the dates to keep this order.
            recipe.addedAt = now.addingTimeInterval(-Double(index))
            library.add(recipe)
            added += 1
        }
        library.markStarterSetDone()
        return added
    }
}
