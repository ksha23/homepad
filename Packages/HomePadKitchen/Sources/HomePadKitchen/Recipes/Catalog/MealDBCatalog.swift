import Foundation
import HomePadCore

/// TheMealDB (themealdb.com): about 800 home recipes with photos, ingredients and
/// steps, free with its public key "1" for development and personal use. A
/// supporter key from TheMealDB, kept in the keychain, adds ten-at-a-time random
/// picks for Discover. Their terms allow storing what the API returns, as long as
/// TheMealDB is credited as the source, which every saved recipe does.
public struct MealDBCatalog: RecipeCatalog {
    public let name = "TheMealDB"
    /// The public key TheMealDB documents for development and personal use.
    public static let freeKey = "1"
    static let apiBase = URL(string: "https://www.themealdb.com/api/json/v1/")!
    static let idPrefix = "mealdb:"

    let fetcher: any CatalogFetching
    let supporterKey: @Sendable () -> String?

    /// - Parameters:
    ///   - fetcher: Downloads responses. Tests pass fixtures.
    ///   - supporterKey: Read at call time, so a key entered in Settings applies at once.
    public init(fetcher: any CatalogFetching = URLSessionCatalogFetcher(), supporterKey: @escaping @Sendable () -> String? = { nil }) {
        self.fetcher = fetcher
        self.supporterKey = supporterKey
    }

    // MARK: RecipeCatalog

    public func search(_ query: String) async throws -> [CatalogRecipe] {
        let words = Self.searchWords(in: query)
        guard !words.isEmpty else { return [] }
        let phrase = try await meals("search.php", ["s": words.joined(separator: " ")])
        let keywords = words.filter { $0.count >= 3 && !["and", "with"].contains($0) }
        guard phrase.isEmpty, keywords.count > 1 else { return phrase }

        // Names must contain the whole phrase, so "curry chicken" finds nothing.
        // Search each word and rank by how many of the words each recipe matches.
        var pool: [String: CatalogRecipe] = [:]
        for word in keywords.prefix(3) {
            for result in try await meals("search.php", ["s": word]) { pool[result.id] = result }
        }
        let scored = pool.values.map { ($0, Self.matchCount(of: keywords, in: $0)) }.filter { $0.1 > 0 }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.recipe.title < $1.0.recipe.title }
            .prefix(24)
            .map(\.0)
    }

    public func recipe(id: String) async throws -> CatalogRecipe? {
        guard id.hasPrefix(Self.idPrefix) else { return nil }
        return try await meals("lookup.php", ["i": String(id.dropFirst(Self.idPrefix.count))]).first
    }

    public func discover(count: Int) async throws -> [CatalogRecipe] {
        if hasSupporterKey, let picks = try? await meals("randomselection.php", [:]), picks.count >= count / 2 {
            return Array(picks.prefix(count))
        }
        // The free key answers one random recipe per request.
        let outcomes = await withTaskGroup(of: Result<[CatalogRecipe], Error>.self) { group in
            for _ in 0..<count {
                group.addTask {
                    do { return .success(try await meals("random.php", [:])) } catch { return .failure(error) }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        var seen = Set<String>()
        let picks = outcomes.flatMap { (try? $0.get()) ?? [] }.filter { seen.insert($0.id).inserted }
        if picks.isEmpty, case .failure(let error)? = outcomes.first { throw error }
        return picks
    }

    // MARK: Links

    /// The catalog ID for a TheMealDB page link ("themealdb.com/meal/52820" or
    /// "meal.php?c=52820"), so such links import through the API. TheMealDB asks
    /// apps not to scrape its pages.
    public func catalogID(for url: URL) -> String? {
        guard let host = url.host()?.lowercased(), host.hasSuffix("themealdb.com") else { return nil }
        if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "c" })?.value,
           id.allSatisfy(\.isNumber), !id.isEmpty {
            return Self.idPrefix + id
        }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "meal"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1].prefix { $0.isNumber }
        return id.isEmpty ? nil : Self.idPrefix + id
    }

    // MARK: Requests

    var hasSupporterKey: Bool { !(supporterKey()?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }

    func endpoint(_ path: String, _ query: [String: String]) -> URL {
        let key = hasSupporterKey ? (supporterKey() ?? "").trimmingCharacters(in: .whitespaces) : Self.freeKey
        var components = URLComponents(url: Self.apiBase.appending(path: key).appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components?.url ?? Self.apiBase
    }

    private func meals(_ path: String, _ query: [String: String]) async throws -> [CatalogRecipe] {
        let data = try await fetcher.data(for: endpoint(path, query))
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw RecipeCatalogError.unavailable("Its answer could not be read.")
        }
        return (json["meals"]?.arrayValue ?? []).compactMap(MealDBRecipeMapper.result)
    }

    // MARK: Query words

    private static let fillerWords: Set<String> = ["a", "an", "the", "recipe", "recipes", "some", "find", "me", "please", "dish", "for", "how", "to", "make"]

    /// Lowercased words without filler such as "recipe" or "find me".
    static func searchWords(in query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’-")).inverted)
            .filter { !$0.isEmpty && !fillerWords.contains($0) }
    }

    /// How many of `words` appear in a result's title, kind, tags or ingredients.
    static func matchCount(of words: [String], in result: CatalogRecipe) -> Int {
        let haystack = ([result.recipe.title, result.cuisine ?? "", result.category ?? ""]
            + result.recipe.tags + result.recipe.ingredients).joined(separator: " ").lowercased()
        return words.filter { word in
            haystack.contains(word) || (word.count > 3 && word.hasSuffix("s") && haystack.contains(String(word.dropLast())))
        }.count
    }
}
