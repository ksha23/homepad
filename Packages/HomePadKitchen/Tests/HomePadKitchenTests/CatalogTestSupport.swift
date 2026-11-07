import Foundation
import HomePadCore
@testable import HomePadKitchen

/// Answers TheMealDB requests from fixture files and records every request.
/// Keys are the endpoint and query, for example "search.php?s=chicken curry".
/// Unknown requests get TheMealDB's empty answer, `{"meals":null}`.
final class FixtureCatalogFetcher: CatalogFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    private let fixtures: [String: String]
    private let isOffline: Bool

    init(_ fixtures: [String: String] = [:], isOffline: Bool = false) {
        self.fixtures = fixtures
        self.isOffline = isOffline
    }

    var requests: [URL] { lock.withLock { recorded } }

    func data(for url: URL) async throws -> Data {
        lock.withLock { recorded.append(url) }
        if isOffline { throw RecipeCatalogError.offline }
        guard let name = fixtures[Self.key(for: url)] else { return Data(#"{"meals":null}"#.utf8) }
        guard let file = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: file)
    }

    static func key(for url: URL) -> String {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&") ?? ""
        return url.lastPathComponent + "?" + query
    }
}

/// A catalog with fixed answers, for the starter set, Discover, search and the tools.
final class StubCatalog: RecipeCatalog, @unchecked Sendable {
    let name = "TheMealDB"
    private let lock = NSLock()
    private var offline = false
    private var lookups = 0
    let recipes: [String: CatalogRecipe]
    let searchResults: [CatalogRecipe]

    init(recipes: [CatalogRecipe] = [], searchResults: [CatalogRecipe] = []) {
        self.recipes = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.searchResults = searchResults
    }

    var isOffline: Bool {
        get { lock.withLock { offline } }
        set { lock.withLock { offline = newValue } }
    }

    var lookupCount: Int { lock.withLock { lookups } }

    func search(_ query: String) async throws -> [CatalogRecipe] {
        if isOffline { throw RecipeCatalogError.offline }
        return searchResults
    }

    func recipe(id: String) async throws -> CatalogRecipe? {
        lock.withLock { lookups += 1 }
        if isOffline { throw RecipeCatalogError.offline }
        return recipes[id]
    }

    func discover(count: Int) async throws -> [CatalogRecipe] {
        if isOffline { throw RecipeCatalogError.offline }
        return Array(searchResults.prefix(count))
    }

    func catalogID(for url: URL) -> String? {
        MealDBCatalog().catalogID(for: url)
    }

    /// A small catalog recipe with a TheMealDB style ID and page link.
    static func sample(_ number: Int, title: String? = nil) -> CatalogRecipe {
        let recipe = Recipe(title: title ?? "Recipe \(number)", source: "TheMealDB",
                            sourceURL: URL(string: "https://www.themealdb.com/meal/\(number)"),
                            ingredients: ["1 cup rice", "2 eggs"], sections: [RecipeSection(steps: ["Cook for 10 minutes.", "Serve."])])
        return CatalogRecipe(id: "mealdb:\(number)", recipe: recipe, cuisine: "Thai", category: "Chicken")
    }
}
