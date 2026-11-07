import Foundation
import HomePadCore

/// Reads schema.org `recipeInstructions` in all its shapes: one string (plain or
/// HTML), an array of strings, HowToStep and HowToDirection objects, HowToSection
/// groups, ItemLists, and nested arrays of any of these.
enum InstructionsParser {
    private static let stepNumber = NSRegularExpression(compiling: #"^\s*(?:step\s*)?\d{1,2}\s*[.):]\s*|^\s*step\s+\d{1,2}\s*[-–:]?\s*|^\s*•\s*"#)

    /// Sections in order. Loose steps share one untitled section.
    static func sections(from value: JSONValue?, resolve: (JSONValue?) -> JSONValue? = { $0 }) -> [RecipeSection] {
        var sections: [RecipeSection] = []
        var loose: [String] = []

        func flushLoose() {
            if !loose.isEmpty { sections.append(RecipeSection(title: nil, steps: loose)) }
            loose = []
        }

        func visit(_ value: JSONValue?, depth: Int) {
            guard depth < 6, let value = resolve(value) else { return }
            switch value {
            case .string(let string):
                loose += steps(fromText: string)
            case .array(let values):
                values.forEach { visit($0, depth: depth + 1) }
            case .object(let object):
                if JSONLDExtractor.node(object, isType: "HowToTip") { return }
                let isSection = JSONLDExtractor.node(object, isType: "HowToSection")
                    || (object["itemListElement"] != nil && !JSONLDExtractor.node(object, isType: "HowToStep"))
                if isSection {
                    let title = object["name"]?.stringValue.map(HTMLText.plainText)
                    let inner = InstructionsParser.sections(from: object["itemListElement"], resolve: resolve)
                    let innerSteps = inner.flatMap(\.steps)
                    guard !innerSteps.isEmpty else { return }
                    if title?.isEmpty ?? true {
                        loose += innerSteps
                    } else {
                        flushLoose()
                        sections.append(RecipeSection(title: title, steps: innerSteps))
                    }
                } else if let nested = object["itemListElement"] ?? object["item"] {
                    visit(nested, depth: depth + 1)
                } else if let text = (object["text"] ?? object["name"] ?? object["description"])?.stringValue {
                    loose += steps(fromText: text)
                }
            default:
                break
            }
        }

        visit(value, depth: 0)
        flushLoose()
        return sections
    }

    /// Splits a block of instruction text into steps. HTML lists and paragraphs
    /// become one step each, plain text splits on line breaks.
    static func steps(fromText text: String) -> [String] {
        let lines: [String]
        if text.range(of: #"<\s*(li|p|br|div)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            lines = HTMLText.lines(fromHTML: text)
        } else {
            lines = HTMLText.decodeEntities(text).components(separatedBy: .newlines)
        }
        return lines.map(cleanStep).filter { !$0.isEmpty }
    }

    /// Removes tags, numbering ("1.", "Step 2:") and bullets.
    static func cleanStep(_ text: String) -> String {
        let plain = HTMLText.plainText(text)
        let range = NSRange(plain.startIndex..., in: plain)
        return stepNumber.stringByReplacingMatches(in: plain, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
