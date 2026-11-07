import Foundation

/// What an ingredient is called on a shopping list, and the key two lines are
/// matched by. "1 medium yellow onion, chopped" and "2 yellow onions" are both
/// "yellow onion": sizes, preparation, notes after a comma and words in
/// parentheses are left out, and the last word is made singular.
enum GroceryName {
    /// The name to show, as the recipe wrote it without its notes, and the key.
    struct Cleaned: Hashable {
        var name: String
        var key: String
    }

    /// Words before a name that say how big an item is.
    private static let sizes: Set<String> = ["large", "medium", "small", "extra-large", "jumbo", "big"]

    /// Words before a name that say how it is prepared or served, not what to
    /// buy. Words that name a product ("whole milk", "hot sauce", "crushed red
    /// pepper", "ground beef") are not here.
    private static let preparation: Set<String> = [
        "fresh", "freshly", "ripe", "cold", "warm", "boiling", "lukewarm", "chilled", "softened", "melted",
        "chopped", "diced", "minced", "sliced", "grated", "shredded", "peeled", "cubed", "halved",
        "finely", "roughly", "coarsely", "thinly", "thickly", "lightly", "packed", "heaping", "level",
    ]

    /// Packaged goods whose preparation names the product: a can of diced
    /// tomatoes is not the same thing as tomatoes.
    private static let packageUnits: Set<CookingUnit> = [.can, .jar, .package, .bottle]

    /// Notes at the end of a name, after the thing to buy.
    private static let trailingNote = NSRegularExpression(compiling:
        #"\s+(?:for (?:serving|garnish|garnishing|frying|greasing|dusting|the pan)|to taste|optional|divided|as needed|if desired|or more|or to taste|at room temperature)\b.*$"#)
    private static let parenthetical = NSRegularExpression(compiling: #"\([^)]*\)"#)

    /// Nothing to buy: water from the tap and ice from the freezer.
    private static let notGroceries: Set<String> = ["water", "ice", "ice cube"]

    /// Cleans an ingredient's name. Nil when there is nothing to buy: a
    /// heading such as "For the sauce:", an empty line, or tap water.
    /// - Parameter unit: The amount's unit, so packaged goods keep their words.
    static func clean(_ written: String, unit: CookingUnit? = nil) -> Cleaned? {
        var text = written.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(":") || text.lowercased().hasPrefix("for the ") { return nil }
        text = parenthetical.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        if let cut = text.firstIndex(where: { $0 == "," || $0 == ";" }) { text = String(text[..<cut]) }
        if let plus = text.range(of: " plus ", options: .caseInsensitive) { text = String(text[..<plus.lowerBound]) }
        text = trailingNote.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")

        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first?.lowercased() == "of" { words.removeFirst() }
        let keepsPreparation = unit.map(packageUnits.contains) ?? false
        while words.count > 1, let first = words.first?.lowercased().trimmingCharacters(in: .punctuationCharacters),
              sizes.contains(first) || (!keepsPreparation && preparation.contains(first)) {
            words.removeFirst()
        }
        let name = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .:*-–"))
        guard name.contains(where: \.isLetter) else { return nil }
        let key = key(for: name)
        guard !notGroceries.contains(key) else { return nil }
        return Cleaned(name: name, key: key)
    }

    /// Splits a count unit off the end of a name that has no unit of its own:
    /// "garlic cloves" is cloves of garlic, so it merges with "2 cloves garlic".
    static func trailingCountUnit(in name: String) -> (name: String, unit: CookingUnit)? {
        var words = name.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last,
              let found = CookingUnit.match(atStartOf: Substring(last)), found.length == last.count,
              found.unit.kind == .count else { return nil }
        words.removeLast()
        return (words.joined(separator: " "), found.unit)
    }

    /// The matching key: lower case, single spaces, the last word singular.
    static func key(for name: String) -> String {
        var words = name.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let last = words.popLast() else { return "" }
        words.append(singular(last))
        return words.joined(separator: " ")
    }

    /// "onions" to "onion", "berries" to "berry", "cookies" to "cookie",
    /// "tomatoes" to "tomato", "peaches" to "peach". Words that only look
    /// plural ("hummus", "asparagus", "swiss") stay as they are.
    static func singular(_ word: String) -> String {
        let lower = word.lowercased()
        guard lower.count > 3, lower.hasSuffix("s") else { return lower }
        if lower.hasSuffix("ss") || lower.hasSuffix("us") || lower.hasSuffix("is") { return lower }
        if lower.hasSuffix("ies") {
            // Cookie, brownie, veggie and pie end in "ie". Berry, cherry and anchovy end in "y".
            let stem = String(lower.dropLast(3))
            return ["k", "n", "g", "p", "h"].contains(where: { stem.hasSuffix($0) }) ? String(lower.dropLast()) : stem + "y"
        }
        if lower.hasSuffix("oes") { return String(lower.dropLast(2)) }
        if ["ches", "shes", "xes", "zes"].contains(where: { lower.hasSuffix($0) }) { return String(lower.dropLast(2)) }
        return String(lower.dropLast())
    }

    /// The name with its last word plural, for a count above one written in
    /// the singular: "onion" to "onions", "berry" to "berries".
    static func plural(_ name: String) -> String {
        let start = name.lastIndex(of: " ").map { name.index(after: $0) } ?? name.startIndex
        let head = String(name[..<start])
        let word = String(name[start...])
        let lower = word.lowercased()
        // Already plural.
        guard singular(lower) == lower else { return name }
        if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) {
            return head + word.dropLast() + "ies"
        }
        if ["tomato", "potato"].contains(lower) || ["ch", "sh", "x", "z", "s"].contains(where: { lower.hasSuffix($0) }) {
            return head + word + "es"
        }
        return head + word + "s"
    }
}
