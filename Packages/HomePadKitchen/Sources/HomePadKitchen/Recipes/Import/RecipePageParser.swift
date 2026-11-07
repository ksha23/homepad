import Foundation

/// Why a recipe could not be imported.
public enum RecipeImportError: LocalizedError, Sendable {
    case invalidURL
    case download(String)
    case noRecipeFound
    case emptyText

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "That does not look like a web address."
        case .download(let reason): "The page could not be downloaded. \(reason)"
        case .noRecipeFound: "No recipe was found on that page."
        case .emptyText: "There was no text to read a recipe from."
        }
    }
}

/// Reads a recipe from a web page. Tries schema.org JSON-LD first (what Google
/// and HomeView use), then microdata, then headings and lists in the page text.
/// Open Graph tags fill in a missing title, image or site name.
public enum RecipePageParser {
    public static func parse(html: String, pageURL: URL?) throws -> Recipe {
        let structured: Recipe? = JSONLDExtractor.recipe(in: html).flatMap { found in
            SchemaRecipeMapper(node: found.node, index: found.index, pageURL: pageURL).recipe()
        }
        let pageTitle = HTMLText.meta("og:title", in: html) ?? HTMLText.firstElementText("h1", in: html)
            ?? HTMLText.firstElementText("title", in: html)

        var recipe: Recipe
        if let structured, structured.isUsable {
            recipe = structured
        } else if let microdata = MicrodataRecipeParser.parse(html: html, pageURL: pageURL) {
            recipe = microdata
        } else if let heuristic = HeuristicRecipeParser.parse(lines: HTMLText.lines(fromHTML: html), title: pageTitle, requireHeadings: true) {
            recipe = heuristic
            recipe.sourceURL = pageURL
        } else {
            throw RecipeImportError.noRecipeFound
        }

        if recipe.imageURL == nil, let image = HTMLText.meta("og:image", in: html) {
            recipe.imageURL = URL(string: image, relativeTo: pageURL)?.absoluteURL
        }
        if recipe.summary == nil { recipe.summary = HTMLText.meta("og:description", in: html) }
        recipe.source = HTMLText.meta("og:site_name", in: html) ?? recipe.source ?? pageURL.flatMap(siteName)
        return recipe
    }

    /// "seriouseats.com" from "https://www.seriouseats.com/...".
    static func siteName(from url: URL) -> String? {
        guard var host = url.host() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
