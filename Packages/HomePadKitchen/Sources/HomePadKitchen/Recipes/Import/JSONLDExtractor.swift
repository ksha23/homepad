import Foundation
import HomePadCore

/// Pulls schema.org JSON-LD out of a page and finds the Recipe node in it.
///
/// Real pages put the recipe in many shapes: a single object, a top-level array,
/// a Yoast-style `@graph`, nested under `mainEntity`, with `@type` as an array
/// (`["Recipe", "NewsArticle"]`) or a full IRI (`http://schema.org/Recipe`).
/// Some blocks are not valid JSON (raw newlines in strings, HTML comments,
/// trailing semicolons, entity-encoded quotes), so each block is repaired before parsing.
enum JSONLDExtractor {
    private static let scriptBlock = NSRegularExpression(compiling:
        #"<script\b[^>]*\btype\s*=\s*["']?application/ld\+json["']?[^>]*>([\s\S]*?)</script\s*>"#)

    /// Every JSON-LD block on the page that parses.
    static func documents(in html: String) -> [JSONValue] {
        scriptBlock.matches(in: html).compactMap { match in
            match.group(1, in: html).flatMap(parse)
        }
    }

    /// The first Recipe node across all blocks, with an index of every `@id` node
    /// so references like `"author": {"@id": "#/schema/person/1"}` can be resolved.
    static func recipe(in html: String) -> (node: [String: JSONValue], index: [String: [String: JSONValue]])? {
        let documents = documents(in: html)
        var index: [String: [String: JSONValue]] = [:]
        documents.forEach { collectIDs($0, into: &index, depth: 0) }
        for document in documents {
            if let node = findRecipe(in: document, depth: 0) { return (node, index) }
        }
        return nil
    }

    /// Parses one block, repairing the usual defects.
    static func parse(_ raw: String) -> JSONValue? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for wrapper in ["<!--", "-->", "//<![CDATA[", "//]]>", "<![CDATA[", "]]>"] {
            text = text.replacingOccurrences(of: wrapper, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }

        if let value = try? JSONValue.parse(text) { return value }
        let repaired = escapeControlCharactersInStrings(text)
        if let value = try? JSONValue.parse(repaired) { return value }
        if text.contains("&quot;"), let value = try? JSONValue.parse(HTMLText.decodeEntities(repaired)) { return value }
        return nil
    }

    /// Escapes raw newlines and tabs that appear inside JSON strings, which
    /// browsers tolerate and `JSONDecoder` rejects.
    static func escapeControlCharactersInStrings(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        var inString = false
        var escaped = false
        for character in text {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                } else if character == "\n" || character == "\r\n" || character == "\r" {
                    output += "\\n"
                    continue
                } else if character == "\t" {
                    output += "\\t"
                    continue
                }
            } else if character == "\"" {
                inString = true
            }
            output.append(character)
        }
        return output
    }

    // MARK: Searching

    /// True when a node's `@type` names `type` in any of its spellings.
    static func node(_ node: [String: JSONValue], isType type: String) -> Bool {
        let wanted = type.lowercased()
        let types: [String]
        switch node["@type"] {
        case .string(let value): types = [value]
        case .array(let values): types = values.compactMap(\.stringValue)
        default: types = []
        }
        return types.contains { normalizedType($0) == wanted }
    }

    private static func normalizedType(_ type: String) -> String {
        var value = type.lowercased()
        for prefix in ["https://schema.org/", "http://schema.org/", "schema:"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        return value
    }

    private static func findRecipe(in value: JSONValue, depth: Int) -> [String: JSONValue]? {
        guard depth < 8 else { return nil }
        switch value {
        case .object(let object):
            if node(object, isType: "Recipe") { return object }
            // Look in the usual containers first, then everywhere else.
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"] {
                if let child = object[key], let found = findRecipe(in: child, depth: depth + 1) { return found }
            }
            for (key, child) in object where !["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"].contains(key) {
                if let found = findRecipe(in: child, depth: depth + 1) { return found }
            }
            return nil
        case .array(let values):
            for child in values {
                if let found = findRecipe(in: child, depth: depth + 1) { return found }
            }
            return nil
        default:
            return nil
        }
    }

    private static func collectIDs(_ value: JSONValue, into index: inout [String: [String: JSONValue]], depth: Int) {
        guard depth < 8 else { return }
        switch value {
        case .object(let object):
            if let id = object["@id"]?.stringValue, object.count > 1, index[id] == nil { index[id] = object }
            object.values.forEach { collectIDs($0, into: &index, depth: depth + 1) }
        case .array(let values):
            values.forEach { collectIDs($0, into: &index, depth: depth + 1) }
        default:
            break
        }
    }
}
