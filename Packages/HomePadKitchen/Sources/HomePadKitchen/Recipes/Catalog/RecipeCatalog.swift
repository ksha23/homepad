import Foundation

/// A recipe found in an online catalog, complete enough to preview and save.
public struct CatalogRecipe: Identifiable, Hashable, Sendable {
    /// Stable across launches, for example "mealdb:52820".
    public let id: String
    /// The recipe exactly as it would be saved: ingredients, steps, photo and source link.
    public var recipe: Recipe
    /// A smaller photo for result tiles and shelves.
    public var thumbnailURL: URL?
    /// Where the dish comes from, for example "Japanese".
    public var cuisine: String?
    /// The catalog's own grouping, for example "Chicken" or "Dessert".
    public var category: String?

    public init(id: String, recipe: Recipe, thumbnailURL: URL? = nil, cuisine: String? = nil, category: String? = nil) {
        self.id = id
        self.recipe = recipe
        self.thumbnailURL = thumbnailURL
        self.cuisine = cuisine
        self.category = category
    }

    /// "Japanese · Chicken", or nil when the catalog says neither.
    public var kindLine: String? {
        let parts = [cuisine, category].compactMap { $0 }.filter { !$0.isEmpty && $0 != "Unknown" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Why a catalog request failed. Being offline gets its own wording in the app.
public enum RecipeCatalogError: LocalizedError, Equatable, Sendable {
    case offline
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .offline: "HomePad is offline, so recipes cannot be searched right now."
        case .unavailable(let reason): "Recipe search is not available right now. \(reason)"
        }
    }
}

/// An online source of recipes to search, browse and save. TheMealDB by default.
public protocol RecipeCatalog: Sendable {
    /// Shown as the source of results and in the attribution line, for example "TheMealDB".
    var name: String { get }
    /// Recipes matching a few words, best matches first.
    func search(_ query: String) async throws -> [CatalogRecipe]
    /// One recipe by its `CatalogRecipe.id`, or nil when the catalog no longer has it.
    func recipe(id: String) async throws -> CatalogRecipe?
    /// A few picks to browse. Each call may return different ones.
    func discover(count: Int) async throws -> [CatalogRecipe]
    /// The catalog ID for a link to one of the catalog's own pages, so the link
    /// imports through the catalog instead of its web page.
    func catalogID(for url: URL) -> String?
}

/// Downloads catalog responses. A protocol so tests can answer from fixtures.
public protocol CatalogFetching: Sendable {
    func data(for url: URL) async throws -> Data
}

/// Fetches with `URLSession` and turns connection failures into `RecipeCatalogError.offline`.
public struct URLSessionCatalogFetcher: CatalogFetching {
    public init() {}

    public func data(for url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw RecipeCatalogError.unavailable("The service answered with status \(http.statusCode).")
            }
            return data
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw RecipeCatalogError.offline
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff,
    ]
}
