import Foundation
import HomePadCore

/// Downloads a page. A protocol so tests can import from fixtures.
public protocol RecipePageFetching: Sendable {
    func html(for url: URL) async throws -> String
}

/// Fetches pages with `URLSession`, presenting as Safari because some recipe
/// sites serve bots a page without structured data.
public struct URLSessionPageFetcher: RecipePageFetching {
    public init() {}

    public func html(for url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RecipeImportError.download("The site answered with status \(http.statusCode).")
        }
        let encoding = response.textEncodingName
            .map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
            .map { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding($0)) }
        if let encoding, let text = String(data: data, encoding: encoding) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Imports recipes from web pages and from scanned text.
@MainActor
public struct RecipeImporter {
    let fetcher: any RecipePageFetching
    let catalog: (any RecipeCatalog)?

    /// - Parameter catalog: Links to the catalog's own pages import through its API.
    public init(fetcher: any RecipePageFetching = URLSessionPageFetcher(), catalog: (any RecipeCatalog)? = nil) {
        self.fetcher = fetcher
        self.catalog = catalog
    }

    /// A recipe from a link that was pasted, shared or handed off.
    public func importRecipe(from link: String) async throws -> Recipe {
        guard let url = Self.url(from: link) else { throw RecipeImportError.invalidURL }
        if let catalog, let id = catalog.catalogID(for: url) {
            return try await importRecipe(catalogID: id, from: catalog)
        }
        let html: String
        do {
            html = try await fetcher.html(for: url)
        } catch let error as RecipeImportError {
            throw error
        } catch {
            throw RecipeImportError.download(error.localizedDescription)
        }
        return try RecipePageParser.parse(html: html, pageURL: url)
    }

    private func importRecipe(catalogID id: String, from catalog: any RecipeCatalog) async throws -> Recipe {
        let found: CatalogRecipe?
        do {
            found = try await catalog.recipe(id: id)
        } catch {
            throw RecipeImportError.download(error.localizedDescription)
        }
        guard let found else { throw RecipeImportError.noRecipeFound }
        return found.recipe
    }

    /// A recipe from scanned or pasted text. Uses the AI provider when one is
    /// configured, otherwise heuristics.
    public func importRecipe(fromText text: String, assistant: (any AssistantService)?) async throws -> Recipe {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeImportError.emptyText }
        if let assistant, let structured = await AssistantRecipeStructurer.structure(trimmed, with: assistant) {
            return structured
        }
        guard let recipe = HeuristicRecipeParser.parse(lines: trimmed.components(separatedBy: .newlines), title: nil) else {
            throw RecipeImportError.noRecipeFound
        }
        return recipe
    }

    /// Accepts "example.com/recipe" as well as full links, and finds a link inside shared text.
    nonisolated static func url(from link: String) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        guard !trimmed.contains(" "), trimmed.contains(".") else { return nil }
        return URL(string: "https://" + trimmed)
    }
}
