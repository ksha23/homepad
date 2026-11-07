import Foundation

/// One ingredient line split into amount and the rest:
/// "2 cups (250 g) all-purpose flour, sifted" becomes amount "2 cups (250 g)"
/// and name "all-purpose flour, sifted".
public struct ParsedIngredient: Hashable, Sendable {
    /// The line as written.
    public let original: String
    public let amount: IngredientAmount?
    /// Where the amount sits in `original`, for highlighting.
    public let amountRange: Range<String.Index>?
    /// Everything after the amount, without a leading "of".
    public let name: String

    /// The amount as the source wrote it, for example "1 1/2 cups".
    public var writtenAmount: String? {
        amountRange.map { String(original[$0]) }
    }
}

/// Splits ingredient lines into amount and name.
public enum IngredientParser {
    private static let bullet = NSRegularExpression(compiling: #"^\s*[-–•*▢□◦·]\s*"#)

    public static func parse(_ line: String) -> ParsedIngredient {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (amount, range) = QuantityParser.parseLeading(text) else {
            let name = bullet.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            return ParsedIngredient(original: text, amount: nil, amountRange: nil, name: name)
        }
        var name = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if name.lowercased().hasPrefix("of ") { name = String(name.dropFirst(3)) }
        return ParsedIngredient(original: text, amount: amount, amountRange: range, name: name)
    }
}
