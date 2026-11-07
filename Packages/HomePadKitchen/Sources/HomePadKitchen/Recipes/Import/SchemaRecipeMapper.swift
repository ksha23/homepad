import Foundation
import HomePadCore

/// Turns a schema.org Recipe node into a `Recipe`.
///
/// Handles the field variants seen on real sites: images as strings, arrays or
/// ImageObjects (and `@id` references to them), yields as numbers, strings or
/// arrays, ISO 8601 or plain-text times, and authors or publishers as strings,
/// objects, arrays or references.
struct SchemaRecipeMapper {
    let node: [String: JSONValue]
    /// Every `@id` node in the page, for resolving references.
    let index: [String: [String: JSONValue]]
    let pageURL: URL?

    func recipe() -> Recipe? {
        guard let title = text(node["name"]) ?? text(node["headline"]) else { return nil }
        let yield = RecipeYieldParser.parse(node["recipeYield"] ?? node["yield"])
        return Recipe(
            title: title,
            summary: text(node["description"]),
            source: name(of: node["publisher"]) ?? name(of: node["author"]),
            sourceURL: pageURL ?? url(node["url"]),
            imageURL: image(node["image"]) ?? image(node["thumbnailUrl"]),
            prepTime: time(node["prepTime"]),
            cookTime: time(node["cookTime"]),
            totalTime: time(node["totalTime"]),
            servings: yield.servings,
            yieldText: yield.text,
            ingredients: ingredients(node["recipeIngredient"] ?? node["ingredients"]),
            sections: InstructionsParser.sections(from: node["recipeInstructions"], resolve: resolve),
            tags: tags()
        )
    }

    // MARK: Fields

    private func text(_ value: JSONValue?) -> String? {
        switch resolve(value) {
        case .string(let string):
            let plain = HTMLText.plainText(string)
            return plain.isEmpty ? nil : plain
        case .array(let values):
            return values.lazy.compactMap { self.text($0) }.first
        case .number(let number):
            return number.formatted()
        default:
            return nil
        }
    }

    private func name(of value: JSONValue?) -> String? {
        switch resolve(value) {
        case .string(let string): return text(.string(string))
        case .object(let object): return text(object["name"])
        case .array(let values): return values.lazy.compactMap { self.name(of: $0) }.first
        default: return nil
        }
    }

    private func time(_ value: JSONValue?) -> TimeInterval? {
        guard let string = text(value) else { return nil }
        return ISO8601Duration.recipeTime(from: string)
    }

    private func ingredients(_ value: JSONValue?) -> [String] {
        let lines: [String]
        switch value {
        case .string(let string): lines = string.components(separatedBy: .newlines)
        case .array(let values): lines = values.compactMap { $0.stringValue ?? self.text($0) }
        default: lines = []
        }
        return lines.map(HTMLText.plainText).filter { !$0.isEmpty }
    }

    private func tags() -> [String] {
        var tags: [String] = []
        for key in ["recipeCategory", "recipeCuisine", "keywords"] {
            switch node[key] {
            case .string(let string): tags += string.split(separator: ",").map { HTMLText.plainText(String($0)) }
            case .array(let values): tags += values.compactMap(\.stringValue).map(HTMLText.plainText)
            default: break
            }
        }
        var seen = Set<String>()
        return tags.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(8).map { $0 }
    }

    // MARK: Images

    /// The best hero image: the largest by declared size or by a "-1200x800" style
    /// file name, else the first one listed.
    private func image(_ value: JSONValue?) -> URL? {
        let candidates = imageCandidates(value)
        let best = candidates.max { $0.area < $1.area } ?? candidates.first
        return best.flatMap { url(.string($0.url)) }
    }

    private struct ImageCandidate {
        let url: String
        let area: Double
    }

    private func imageCandidates(_ value: JSONValue?) -> [ImageCandidate] {
        switch resolve(value) {
        case .string(let string):
            return [ImageCandidate(url: string, area: Self.areaFromFileName(string))]
        case .array(let values):
            return values.flatMap { imageCandidates($0) }
        case .object(let object):
            guard let link = (object["url"] ?? object["contentUrl"])?.stringValue else { return [] }
            let width = object["width"].flatMap(dimension) ?? 0
            let height = object["height"].flatMap(dimension) ?? 0
            let area = width * height > 0 ? width * height : Self.areaFromFileName(link)
            return [ImageCandidate(url: link, area: area)]
        default:
            return []
        }
    }

    private func dimension(_ value: JSONValue) -> Double? {
        if let number = value.doubleValue { return number }
        if case .object(let object) = value { return object["value"]?.doubleValue }
        return nil
    }

    private static let sizeInName = NSRegularExpression(compiling: #"[-_](\d{2,4})x(\d{2,4})(?=[._-])"#)

    static func areaFromFileName(_ link: String) -> Double {
        guard let match = sizeInName.matches(in: link).last,
              let width = match.group(1, in: link).flatMap(Double.init),
              let height = match.group(2, in: link).flatMap(Double.init) else { return 0 }
        return width * height
    }

    // MARK: Helpers

    /// Follows an `{"@id": ...}` reference to its node, when the page defines it.
    func resolve(_ value: JSONValue?) -> JSONValue? {
        guard case .object(let object)? = value, object.count == 1, let id = object["@id"]?.stringValue,
              let target = index[id] else { return value }
        return .object(target)
    }

    private func url(_ value: JSONValue?) -> URL? {
        guard var string = value?.stringValue?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        string = HTMLText.decodeEntities(string)
        if string.hasPrefix("//") { string = "https:" + string }
        if let pageURL, let relative = URL(string: string, relativeTo: pageURL) { return relative.absoluteURL }
        return URL(string: string)
    }
}
