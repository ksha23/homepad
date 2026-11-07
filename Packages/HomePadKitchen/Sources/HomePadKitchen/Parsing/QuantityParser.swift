import Foundation

/// A number or a range of numbers, such as "2" or "2 to 3".
public struct Quantity: Hashable, Sendable {
    public var low: Double
    public var high: Double?

    public init(_ low: Double, high: Double? = nil) {
        self.low = low
        self.high = high
    }

    /// The same amount multiplied, for scaling and unit conversion.
    public func multiplied(by factor: Double) -> Quantity {
        Quantity(low * factor, high: high.map { $0 * factor })
    }

    /// The larger end, for picking display units and plurals.
    public var largest: Double { high ?? low }
}

/// An amount with an optional unit: "1 1/2 cups", "200g", "3", "1 (14.5 oz) can".
public struct IngredientAmount: Hashable, Sendable {
    public var quantity: Quantity
    public var unit: CookingUnit?
    /// True when the source wrote the unit short ("tbsp", "g"), so output stays short.
    public var isAbbreviated: Bool
    /// A package size written between amount and unit, kept as is: "(14.5 oz)".
    public var sizeNote: String?
    /// A second measurement in parentheses after the unit: the "(250 g)" in "2 cups (250 g) flour".
    public var alternate: AlternateAmount?

    public init(quantity: Quantity, unit: CookingUnit?, isAbbreviated: Bool = false,
                sizeNote: String? = nil, alternate: AlternateAmount? = nil) {
        self.quantity = quantity
        self.unit = unit
        self.isAbbreviated = isAbbreviated
        self.sizeNote = sizeNote
        self.alternate = alternate
    }
}

/// The parenthetical second measurement of an amount. A separate type breaks
/// the recursion between `IngredientAmount` and itself.
public struct AlternateAmount: Hashable, Sendable {
    public var quantity: Quantity
    public var unit: CookingUnit
    public var isAbbreviated: Bool
}

/// Reads amounts at the start of ingredient lines and inside step text.
public enum QuantityParser {
    private static let number = NumberGrammar.wordPattern
    private static let leading = NSRegularExpression(compiling:
        #"^\s*(?:[-–•*▢□◦·]\s*)?("# + number + #")(?:\s*(?:-|–|—|to|or)\s*("# + number + #"))?"#)
    private static let inline = NSRegularExpression(compiling:
        #"(?<![\w/.])("# + NumberGrammar.digitPattern + #")(?:\s*(?:-|–|to)\s*("# + NumberGrammar.digitPattern + #"))?"#)
    private static let parenthetical = NSRegularExpression(compiling: #"^\s*\(([^()]{1,40})\)"#)

    /// The amount at the start of an ingredient line and the range it covers.
    public static func parseLeading(_ text: String) -> (amount: IngredientAmount, range: Range<String.Index>)? {
        guard let match = leading.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let quantity = quantity(from: match, in: text),
              let numberRange = Range(match.range(at: 1), in: text),
              let matchEnd = match.swiftRange(in: text)?.upperBound else { return nil }

        var cursor = matchEnd
        var amount = IngredientAmount(quantity: quantity, unit: nil)

        // A package size before the unit: "1 (14.5 oz) can".
        if let (note, end) = parentheses(in: text, from: cursor),
           let (unit, abbreviated, unitEnd) = unit(in: text, from: end) {
            amount.sizeNote = "(" + note + ")"
            amount.unit = unit
            amount.isAbbreviated = abbreviated
            cursor = unitEnd
        } else if let (unit, abbreviated, unitEnd) = unit(in: text, from: cursor) {
            amount.unit = unit
            amount.isAbbreviated = abbreviated
            cursor = unitEnd
        }

        // A second measurement after the unit: "2 cups (250 g)".
        if amount.unit != nil, let (note, end) = parentheses(in: text, from: cursor),
           let (inner, _) = parseLeading(note), let innerUnit = inner.unit, inner.unit?.kind != .count {
            amount.alternate = AlternateAmount(quantity: inner.quantity, unit: innerUnit, isAbbreviated: inner.isAbbreviated)
            cursor = end
        }
        return (amount, numberRange.lowerBound..<cursor)
    }

    /// Measured amounts ("2 cups", "1/2 teaspoon", "200g") anywhere in free text.
    /// Bare numbers without a unit ("Step 2", "350 degrees") are skipped.
    public static func findMeasured(in text: String) -> [(amount: IngredientAmount, range: Range<String.Index>)] {
        inline.matches(in: text).compactMap { match in
            guard let quantity = quantity(from: match, in: text),
                  let range = match.swiftRange(in: text),
                  let (unit, abbreviated, unitEnd) = unit(in: text, from: range.upperBound) else { return nil }
            return (IngredientAmount(quantity: quantity, unit: unit, isAbbreviated: abbreviated), range.lowerBound..<unitEnd)
        }
    }

    // MARK: Pieces

    private static func quantity(from match: NSTextCheckingResult, in text: String) -> Quantity? {
        guard let first = match.group(1, in: text).flatMap(NumberGrammar.value(of:)) else { return nil }
        let second = match.group(2, in: text).flatMap(NumberGrammar.value(of:))
        return Quantity(first, high: second.flatMap { $0 > first ? $0 : nil })
    }

    /// A unit after at most one space, returning whether it was abbreviated and where it ends.
    private static func unit(in text: String, from start: String.Index) -> (CookingUnit, Bool, String.Index)? {
        var cursor = start
        if cursor < text.endIndex, text[cursor] == " " { cursor = text.index(after: cursor) }
        guard cursor < text.endIndex, let found = CookingUnit.match(atStartOf: text[cursor...]) else { return nil }
        let letters = text[cursor...].prefix(found.length).lowercased().filter(\.isLetter)
        let abbreviated = letters.count < 4
            ? !["cup", "can", "jar"].contains(letters)
            : ["tbsp", "tbls", "tsps", "tspn", "pkgs", "floz"].contains(letters)
        return (found.unit, abbreviated, text.index(cursor, offsetBy: found.length))
    }

    private static func parentheses(in text: String, from start: String.Index) -> (String, String.Index)? {
        let rest = String(text[start...])
        guard let match = parenthetical.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
              let inner = match.group(1, in: rest), let range = match.swiftRange(in: rest) else { return nil }
        let consumed = rest.distance(from: rest.startIndex, to: range.upperBound)
        return (inner, text.index(start, offsetBy: consumed))
    }
}
