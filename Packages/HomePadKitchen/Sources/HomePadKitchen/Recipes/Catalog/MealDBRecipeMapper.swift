import Foundation
import HomePadCore

/// Turns one TheMealDB record into a `CatalogRecipe`: up to twenty ingredient and
/// measure pairs, the instruction text in its several shapes, tags and the photo.
/// Saved recipes credit TheMealDB and link to its page, as its terms ask.
enum MealDBRecipeMapper {
    static func result(from meal: JSONValue) -> CatalogRecipe? {
        guard let id = text(meal["idMeal"]), let title = text(meal["strMeal"]) else { return nil }
        let method = MealDBInstructions(meal["strInstructions"]?.stringValue ?? "")
        let image = text(meal["strMealThumb"]).flatMap(URL.init(string:))
        let cuisine = text(meal["strArea"])
        let category = text(meal["strCategory"])
        let tags = [cuisine, category].compactMap { $0 }
            + (text(meal["strTags"])?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [])
        var seenTags = Set<String>()

        let recipe = Recipe(
            title: title,
            summary: text(meal["strSource"]).flatMap(URL.init(string:)).flatMap(RecipePageParser.siteName(from:)).map { "Adapted from \($0)." },
            source: "TheMealDB",
            sourceURL: URL(string: "https://www.themealdb.com/meal/\(id)"),
            imageURL: image,
            prepTime: method.prepTime,
            cookTime: method.cookTime ?? method.stepTime,
            totalTime: method.totalTime,
            ingredients: (1...20).compactMap { index in
                text(meal["strIngredient\(index)"]).map { ingredientLine(measure: text(meal["strMeasure\(index)"]) ?? "", name: $0) }
            },
            sections: method.steps.isEmpty ? [] : [RecipeSection(steps: method.steps)],
            tags: tags.filter { !$0.isEmpty && seenTags.insert($0.lowercased()).inserted }
        )
        return CatalogRecipe(id: MealDBCatalog.idPrefix + id, recipe: recipe,
                             thumbnailURL: image?.appending(path: "medium"), cuisine: cuisine, category: category)
    }

    private static let sizeWords: Set<String> = ["large", "small", "medium", "whole", "big", "thick", "thin"]
    private static let measureWords: Set<String> = ["pinch", "dash", "handful", "sprinkling", "splash", "drizzle", "knob", "bunch", "sprig", "few"]

    /// "4 chicken breast, pounded to 1cm thickness" from measure "4 pounded to 1cm
    /// thickness" and ingredient "chicken breast". The amount leads, as in a cookbook,
    /// so scaling and unit conversion read it.
    static func ingredientLine(measure: String, name: String) -> String {
        let measure = measure.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !measure.isEmpty else { return name }
        if let (_, range) = QuantityParser.parseLeading(measure) {
            let amount = measure[..<range.upperBound].trimmingCharacters(in: .whitespaces)
            let rest = measure[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return "\(amount) \(name)" }
            if sizeWords.contains(rest.lowercased()) { return "\(amount) \(rest.lowercased()) \(name)" }
            return "\(amount) \(name), \(rest)"
        }
        let lowered = measure.lowercased()
        // "Juice of 1" and "Zest of 2" read best before the name.
        if lowered.contains(" of ") || lowered.hasSuffix(" of") { return "\(measure) \(name)" }
        if let last = lowered.split(separator: " ").last, measureWords.contains(String(last)) { return "\(measure) of \(name)" }
        return "\(name), \(lowered)"
    }

    /// Trimmed text, or nil for empty fields (TheMealDB sends "" and " " for unused slots).
    static func text(_ value: JSONValue?) -> String? {
        guard let string = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }
}

/// Steps and times from TheMealDB's free-text instructions. They come as lines,
/// paragraphs, "STEP 1" headings, "01." numbering, or one block, sometimes
/// with a "Prep:15min › Cook:30min › Ready in:45min" line first.
struct MealDBInstructions {
    private(set) var steps: [String] = []
    private(set) var prepTime: TimeInterval?
    private(set) var cookTime: TimeInterval?
    private(set) var totalTime: TimeInterval?

    private static let stepHeading = NSRegularExpression(compiling: #"^(?:step\s*)?\d{1,2}\s*[.):]?$|^step\s*\d{1,2}\s*[-–:]?$"#)
    private static let timeField = NSRegularExpression(compiling: #"\b(prep|cook|ready in|total)(?:\s*time)?\s*:\s*([^›|•]+)"#)
    private static let digitThenLetter = NSRegularExpression(compiling: #"(\d)([a-z])"#)

    init(_ raw: String) {
        let lines = HTMLText.decodeEntities(raw)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for line in lines where !line.isEmpty {
            let range = NSRange(line.startIndex..., in: line)
            if Self.stepHeading.firstMatch(in: line, range: range) != nil { continue }
            if steps.isEmpty, readTimes(from: line) { continue }
            let step = InstructionsParser.cleanStep(line)
            if !step.isEmpty { steps.append(step) }
        }
    }

    /// The times the steps state, added up: TheMealDB has no time fields, so this
    /// is the best honest figure, and a lower bound. Nil under ten minutes, where
    /// steps that state only a soak or a sear would make a dish look quicker than it is.
    var stepTime: TimeInterval? {
        let seconds = steps.reduce(0.0) { sum, step in
            sum + DurationExtractor.extract(from: step).reduce(0) { $0 + min($1.lowerBound, 4 * 3600) }
        }
        return seconds >= 600 ? seconds : nil
    }

    /// Reads a "Prep: … › Cook: …" line. Returns false for an ordinary step.
    private mutating func readTimes(from line: String) -> Bool {
        guard line.count < 120 else { return false }
        let matches = Self.timeField.matches(in: line)
        guard !matches.isEmpty, matches[0].range.location < 3 else { return false }
        for match in matches {
            guard let kind = match.group(1, in: line)?.lowercased(), let value = match.group(2, in: line) else { continue }
            let spaced = Self.digitThenLetter.stringByReplacingMatches(
                in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "$1 $2")
            guard let seconds = DurationExtractor.extract(from: spaced).first?.upperBound else { continue }
            switch kind {
            case "prep": prepTime = seconds
            case "cook": cookTime = seconds
            default: totalTime = seconds
            }
        }
        return true
    }
}
