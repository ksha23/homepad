import Foundation

/// The ways recipes write numbers: "2", "1.5", "1/2", "1 1/2", "1½", "½",
/// "one", "a", "half an". Shared by the quantity and duration parsers so both
/// read numbers the same way.
enum NumberGrammar {
    /// Unicode vulgar fractions and their values.
    static let vulgarFractions: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75,
        "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8, "⅙": 1.0 / 6, "⅚": 5.0 / 6,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875,
    ]

    /// Number words recipes use, longest first so "forty-five" wins over "forty".
    static let words: [(String, Double)] = [
        ("forty-five", 45), ("thirty-five", 35), ("twenty-five", 25),
        ("fifteen", 15), ("twenty", 20), ("thirty", 30), ("forty", 40), ("fifty", 50),
        ("sixty", 60), ("ninety", 90), ("eleven", 11), ("twelve", 12),
        ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6),
        ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
    ]

    private static let vulgarClass = "[" + String(vulgarFractions.keys) + "]"

    /// Mixed numbers, fractions, unicode fractions and decimals, as regex alternatives.
    /// Mixed forms come first because ICU alternation takes the first branch that fits.
    private static let digitAlternatives =
        #"\d+\s+and\s+\d+\s*[/⁄]\s*\d+|\d+\s+\d+\s*[/⁄]\s*\d+|\d+\s*"# + vulgarClass
        + #"|\d+\s*[/⁄]\s*\d+|"# + vulgarClass + #"|\d+(?:\.\d+)?|\.\d+"#

    /// A number written with digits or fraction characters.
    static let digitPattern = "(?:" + digitAlternatives + ")"

    /// Digits plus words ("one", "a", "an", "half an", "a couple of"). Words must end
    /// at a word boundary so "ten" does not match inside "tender".
    static let wordPattern: String = {
        let wordList = words.map(\.0).joined(separator: "|")
        return "(?:" + digitAlternatives + "|(?:" + wordList
            + #"|half\s+an?|a\s+half|a\s+couple(?:\s+of)?|an|a)(?![A-Za-z]))"#
    }()

    /// Reads the value of a number written in any supported form. Nil if unreadable.
    static func value(of text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let word = wordValue(trimmed) { return word }

        // "1 and 1/2" reads like "1 1/2".
        let normalized = trimmed
            .replacingOccurrences(of: " and ", with: " ")
            .replacingOccurrences(of: "⁄", with: "/")

        // Split a trailing unicode fraction: "1½" or "1 ½".
        if let last = normalized.last, let fraction = vulgarFractions[last] {
            let whole = normalized.dropLast().trimmingCharacters(in: .whitespaces)
            if whole.isEmpty { return fraction }
            guard let wholeValue = Double(whole) else { return nil }
            return wholeValue + fraction
        }

        let parts = normalized.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count == 2, let whole = Double(parts[0]), let fraction = fractionValue(parts[1]) {
            return whole + fraction
        }
        let joined = normalized.replacingOccurrences(of: " ", with: "")
        if let fraction = fractionValue(joined) { return fraction }
        return Double(joined)
    }

    private static func wordValue(_ text: String) -> Double? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        switch collapsed {
        case "a", "an": return 1
        case "half a", "half an", "a half": return 0.5
        case "a couple", "a couple of": return 2
        default: return words.first { $0.0 == collapsed }?.1
        }
    }

    private static func fractionValue(_ text: String) -> Double? {
        let pieces = text.split(separator: "/")
        guard pieces.count == 2, let numerator = Double(pieces[0]), let denominator = Double(pieces[1]),
              denominator != 0 else { return nil }
        return numerator / denominator
    }
}

extension NSRegularExpression {
    /// Compiles a pattern that is known to be valid at build time.
    convenience init(compiling pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
        do {
            try self.init(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid regular expression \(pattern): \(error)")
        }
    }

    /// All matches in a Swift string.
    func matches(in text: String) -> [NSTextCheckingResult] {
        matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

extension NSTextCheckingResult {
    /// The text of capture group `index`, or nil when it did not participate.
    func group(_ index: Int, in text: String) -> String? {
        let range = self.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// The whole match as a Swift range.
    func swiftRange(in text: String) -> Range<String.Index>? {
        Range(range, in: text)
    }
}
