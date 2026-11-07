import Foundation

/// Builds a recipe from loose lines of text: a page without structured data,
/// or text scanned from a cookbook with the camera.
///
/// It looks for "Ingredients" and "Instructions" style headings first. Without
/// them it classifies lines: short lines that start with an amount are
/// ingredients, numbered or sentence-like lines are steps. OCR line wraps are
/// joined back into whole steps.
enum HeuristicRecipeParser {
    private static let ingredientHeading = NSRegularExpression(compiling:
        #"^(?:•\s*)?(?:ingredients?|what you(?:'|’)?ll need|you will need|shopping list)\b[^a-z]*$"#)
    private static let stepHeading = NSRegularExpression(compiling:
        #"^(?:•\s*)?(?:instructions|directions|method|preparation|steps|how to make(?: it)?)\b[^a-z]*$"#)
    private static let stopHeading = NSRegularExpression(compiling:
        #"^(?:•\s*)?(?:notes?|nutrition(?: facts| information)?|tips?|video|related|comments?|reviews?|more recipes|you may also like|recipe notes|storage)\b[^a-z]*$"#)
    private static let numberedStep = NSRegularExpression(compiling: #"^\s*(?:step\s*)?\d{1,2}\s*[.):]\s+|^\s*step\s+\d{1,2}\b"#)
    private static let servingsPattern = NSRegularExpression(compiling: #"\b(?:serves|servings|yield|yields|makes)\s*:?\s*(\d{1,3})"#)
    /// "Prep time: 10 min", "Cook: 15 minutes". The word "time" or a colon is required
    /// so a step such as "Cook on a griddle 2 minutes" is not read as the cook time.
    private static let timeLine = NSRegularExpression(compiling: #"^(prep|cook|total)(?:\s*time\s*:?|\s*:)\s*(.+)$"#)

    /// A recipe from `lines`, or nil when there is no clear ingredient list and method.
    /// - Parameter requireHeadings: Web pages need "Ingredients" and "Instructions"
    ///   headings. Scanned text may also be classified line by line.
    static func parse(lines rawLines: [String], title: String?, requireHeadings: Bool = false) -> Recipe? {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        guard let blocks = headedBlocks(in: lines) ?? (requireHeadings ? nil : classify(lines)) else { return nil }
        let (ingredients, steps) = blocks
        guard !ingredients.isEmpty, !steps.isEmpty else { return nil }

        let resolvedTitle = title ?? lines.first { line in
            !matches(ingredientHeading, line) && QuantityParser.parseLeading(line) == nil && line.count < 80
        } ?? "Untitled Recipe"
        let joined = lines.joined(separator: "\n")
        var recipe = Recipe(title: resolvedTitle, ingredients: ingredients, sections: [RecipeSection(steps: steps)])
        recipe.servings = firstCapture(servingsPattern, in: joined).flatMap(Int.init)
        for line in lines.prefix(40) {
            guard let match = timeLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let kind = match.group(1, in: line)?.lowercased(), let value = match.group(2, in: line),
                  let seconds = DurationExtractor.extract(from: value).first?.upperBound else { continue }
            switch kind {
            case "prep": recipe.prepTime = recipe.prepTime ?? seconds
            case "cook": recipe.cookTime = recipe.cookTime ?? seconds
            default: recipe.totalTime = recipe.totalTime ?? seconds
            }
        }
        return recipe
    }

    // MARK: Headed layout

    /// Ingredients and steps found under headings. The ingredient heading must be
    /// followed by lines that look like ingredients, so a "Jump to Ingredients"
    /// link or a table of contents does not count.
    private static func headedBlocks(in lines: [String]) -> ([String], [String])? {
        let candidates = lines.indices.filter { matches(ingredientHeading, lines[$0]) }
        guard let start = candidates.first(where: { looksLikeIngredients(after: $0, in: lines) }),
              let stepStart = lines.indices.first(where: { $0 > start && matches(stepHeading, lines[$0]) }) else { return nil }
        let ingredients = lines[(start + 1)..<stepStart]
            .filter { !isSubheading($0) }
            .map(stripBullet)
        var stepLines: [String] = []
        for line in lines[(stepStart + 1)...] {
            if matches(stopHeading, line) || matches(ingredientHeading, line) { break }
            stepLines.append(line)
        }
        return (Array(ingredients.prefix(60)), joinSteps(stepLines).prefix(60).map { $0 })
    }

    private static func looksLikeIngredients(after index: Int, in lines: [String]) -> Bool {
        let window = lines.dropFirst(index + 1).prefix(6)
            .prefix { !isHeading($0) }
        return window.filter { QuantityParser.parseLeading(stripBullet($0)) != nil }.count >= 2
    }

    private static func isHeading(_ line: String) -> Bool {
        matches(ingredientHeading, line) || matches(stepHeading, line) || matches(stopHeading, line)
    }

    /// "For the sauce:" style group labels inside an ingredient list.
    private static func isSubheading(_ line: String) -> Bool {
        line.hasSuffix(":") && QuantityParser.parseLeading(line) == nil && line.count < 40
    }

    // MARK: Unheaded layout

    private static func classify(_ lines: [String]) -> ([String], [String]) {
        var ingredients: [String] = []
        var stepLines: [String] = []
        for line in lines where !matches(ingredientHeading, line) && !matches(stepHeading, line) {
            let bare = stripBullet(line)
            let isNumbered = matches(numberedStep, line)
            if !isNumbered, stepLines.isEmpty, looksLikeIngredient(bare) {
                ingredients.append(bare)
            } else if isNumbered || !stepLines.isEmpty || (!ingredients.isEmpty && bare.count > 25) {
                stepLines.append(line)
            }
        }
        return ingredients.count >= 2 ? (ingredients, joinSteps(stepLines)) : ([], [])
    }

    /// A short line that starts with a written amount ("2 eggs", "½ cup milk") or an
    /// amount with a unit ("a pinch of salt"). "Ten gadgets we love" is not one.
    private static func looksLikeIngredient(_ line: String) -> Bool {
        guard line.count <= 70, let (amount, _) = QuantityParser.parseLeading(line) else { return false }
        guard let first = line.first else { return false }
        return amount.unit != nil || first.isNumber || NumberGrammar.vulgarFractions[first] != nil
    }

    /// Joins wrapped lines into whole steps. A new step starts at a number or
    /// bullet, or after a line that ends a sentence.
    private static func joinSteps(_ lines: [String]) -> [String] {
        var steps: [String] = []
        for line in lines {
            let startsNew = matches(numberedStep, line) || line.hasPrefix("•")
            let cleaned = InstructionsParser.cleanStep(line)
            guard !cleaned.isEmpty else { continue }
            if let last = steps.last, !startsNew, !endsSentence(last) {
                steps[steps.count - 1] = last + " " + cleaned
            } else {
                steps.append(cleaned)
            }
        }
        return steps
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return true }
        return ".!?:)".contains(last)
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line
        while let first = text.first, "•-–*▢□◦·".contains(first) { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ regex: NSRegularExpression, _ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func firstCapture(_ regex: NSRegularExpression, in text: String) -> String? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.group(1, in: text)
    }
}
