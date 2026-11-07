import Foundation

/// Fallback for older pages that mark recipes up with schema.org microdata
/// (`itemscope itemtype="http://schema.org/Recipe"` and `itemprop` attributes)
/// instead of JSON-LD.
enum MicrodataRecipeParser {
    private static let recipeScope = NSRegularExpression(compiling: #"itemtype\s*=\s*["']https?://schema\.org/Recipe["']"#)
    private static let voidTags: Set<String> = ["meta", "img", "link", "input", "source"]

    static func parse(html: String, pageURL: URL?) -> Recipe? {
        guard let scopeMatch = recipeScope.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let scopeStart = Range(scopeMatch.range, in: html)?.lowerBound else { return nil }
        let scope = String(html[scopeStart...])

        guard let title = values("name", in: scope).first else { return nil }
        let ingredients = values("recipeIngredient", in: scope) + values("ingredients", in: scope)
        let instructionBlocks = elements("recipeInstructions", in: scope)
        let steps = instructionBlocks.flatMap { element in
            InstructionsParser.steps(fromText: element.content ?? element.inner)
        }
        guard !steps.isEmpty else { return nil }

        let yieldText = values("recipeYield", in: scope).first
        let imageLink = elements("image", in: scope).first.flatMap { element in
            ["src", "content", "href"].lazy.compactMap { HTMLText.attribute($0, in: element.startTag) }.first
        }
        return Recipe(
            title: title,
            summary: values("description", in: scope).first,
            sourceURL: pageURL,
            imageURL: imageLink.flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL },
            prepTime: values("prepTime", in: scope).first.flatMap(ISO8601Duration.recipeTime),
            cookTime: values("cookTime", in: scope).first.flatMap(ISO8601Duration.recipeTime),
            totalTime: values("totalTime", in: scope).first.flatMap(ISO8601Duration.recipeTime),
            servings: yieldText.flatMap(RecipeYieldParser.servings(in:)),
            yieldText: yieldText,
            ingredients: ingredients,
            sections: [RecipeSection(steps: steps)]
        )
    }

    /// An element carrying an `itemprop`.
    struct Element {
        let startTag: String
        let inner: String
        /// A machine value from `content` or `datetime`, which wins over the text.
        var content: String? {
            HTMLText.attribute("content", in: startTag) ?? HTMLText.attribute("datetime", in: startTag)
        }
    }

    /// Text values of every element with `itemprop` = `property`.
    static func values(_ property: String, in html: String) -> [String] {
        elements(property, in: html).compactMap { element in
            let value = element.content ?? HTMLText.plainText(element.inner)
            return value.isEmpty ? nil : value
        }
    }

    /// Every element whose `itemprop` list contains `property`, with its inner HTML.
    static func elements(_ property: String, in html: String) -> [Element] {
        let pattern = #"<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*\bitemprop\s*=\s*["'](?:[^"']*\s)?"#
            + NSRegularExpression.escapedPattern(for: property) + #"(?:\s[^"']*)?["'][^>]*>"#
        let regex = NSRegularExpression(compiling: pattern)
        return regex.matches(in: html).compactMap { match in
            guard let range = match.swiftRange(in: html), let tag = match.group(1, in: html)?.lowercased() else { return nil }
            let startTag = String(html[range])
            if voidTags.contains(tag) || startTag.hasSuffix("/>") {
                return Element(startTag: startTag, inner: "")
            }
            return Element(startTag: startTag, inner: innerHTML(of: tag, in: html, after: range.upperBound))
        }
    }

    /// The markup between a start tag and its matching end tag, counting nested
    /// elements of the same name.
    private static func innerHTML(of tag: String, in html: String, after start: String.Index) -> String {
        let regex = NSRegularExpression(compiling: "<(/?)" + tag + #"\b[^>]*>"#)
        let searchRange = NSRange(start..., in: html)
        var depth = 1
        for match in regex.matches(in: html, range: searchRange) {
            depth += match.group(1, in: html) == "/" ? -1 : 1
            if depth == 0, let end = Range(match.range, in: html)?.lowerBound {
                return String(html[start..<end])
            }
        }
        return String(html[start...].prefix(2000))
    }
}
