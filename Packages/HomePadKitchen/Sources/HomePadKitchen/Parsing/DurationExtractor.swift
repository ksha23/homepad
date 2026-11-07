import Foundation

/// A cooking time found in step text, such as "3 to 5 minutes" or "1 hour 20 min".
public struct DetectedDuration: Hashable, Sendable {
    /// Where it appears in the source text.
    public let range: Range<String.Index>
    /// The words as written, for chip labels.
    public let text: String
    /// Shortest time in seconds ("3" in "3 to 5 minutes").
    public let lowerBound: TimeInterval
    /// Longest time in seconds ("5" in "3 to 5 minutes"). Equal to `lowerBound` for exact times.
    public let upperBound: TimeInterval

    /// True for "3 to 5 minutes", false for "5 minutes".
    public var isRange: Bool { upperBound > lowerBound }
}

/// Finds durations in free text. Handles ranges ("5-7 min", "45 minutes to 1 hour"),
/// compounds ("1 hour 20 min", "1 hr and 15 minutes"), fractions ("1½ hours"),
/// words ("an hour and a half", "half an hour") and abbreviations ("20m").
public enum DurationExtractor {
    enum TimeUnit: Int, Comparable {
        case second = 1, minute = 60, hour = 3600

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        init?(_ text: String) {
            switch text.lowercased().first {
            case "h": self = .hour
            case "m": self = .minute
            case "s": self = .second
            default: return nil
            }
        }
    }

    private static let number = NumberGrammar.wordPattern
    /// Single-letter units only count when glued to a digit ("20m", "1h").
    private static let unit = #"(hours?|hrs?|minutes?|mins?|seconds?|secs?|(?<=\d)h|(?<=\d)m)(?![A-Za-z])"#
    private static let component = NSRegularExpression(compiling:
        #"(?<![\w/.])("# + number + #")(?:\s*(?:-|–|—|to|or)\s*("# + number + #"))?"#
        + #"(?:\s+(?:more|additional|extra|full))?(?:\s*|-)"# + unit + #"(\s+and\s+a\s+half)?"#)

    private static let compoundGap = NSRegularExpression(compiling: #"^\s*,?\s*(?:and\s+)?$"#)
    private static let rangeGap = NSRegularExpression(compiling: #"^\s*(?:-|–|—|to|or)\s*$"#)

    /// One "number unit" match before merging.
    private struct Component {
        var range: Range<String.Index>
        var lower: TimeInterval
        var upper: TimeInterval
        var unit: TimeUnit
    }

    /// Every duration in `text`, in reading order.
    public static func extract(from text: String) -> [DetectedDuration] {
        let components = component.matches(in: text).compactMap { makeComponent($0, in: text) }
        return merge(components, in: text).map { merged in
            DetectedDuration(range: merged.range, text: String(text[merged.range]),
                             lowerBound: merged.lower, upperBound: merged.upper)
        }
    }

    private static func makeComponent(_ match: NSTextCheckingResult, in text: String) -> Component? {
        guard let range = match.swiftRange(in: text),
              let firstText = match.group(1, in: text), let first = NumberGrammar.value(of: firstText),
              let unitText = match.group(3, in: text), let unit = TimeUnit(unitText) else { return nil }
        // "a second time" is not a duration.
        if unit == .second, ["a", "an"].contains(firstText.lowercased()) { return nil }
        let second = match.group(2, in: text).flatMap(NumberGrammar.value(of:))
        let half = match.group(4, in: text) == nil ? 0 : 0.5
        let scale = Double(unit.rawValue)
        let lower = (first + half) * scale
        let upper = ((second ?? first) + half) * scale
        guard lower > 0 else { return nil }
        return Component(range: range, lower: lower, upper: max(lower, upper), unit: unit)
    }

    /// Joins "1 hour" + "20 min" into one compound, and "45 minutes" + "to" + "1 hour" into a range.
    private static func merge(_ components: [Component], in text: String) -> [Component] {
        var result: [Component] = []
        var isRangeOpen = false
        for next in components {
            guard var current = result.last else {
                result.append(next)
                continue
            }
            let gap = String(text[current.range.upperBound..<next.range.lowerBound])
            if next.unit < current.unit, matches(compoundGap, gap) {
                current.upper += next.upper
                if !isRangeOpen { current.lower += next.lower }
                current.range = current.range.lowerBound..<next.range.upperBound
                current.unit = next.unit
                result[result.count - 1] = current
            } else if !isRangeOpen, current.lower == current.upper, matches(rangeGap, gap) {
                current.upper = max(current.lower, next.upper)
                current.range = current.range.lowerBound..<next.range.upperBound
                current.unit = next.unit
                result[result.count - 1] = current
                isRangeOpen = true
            } else {
                result.append(next)
                isRangeOpen = false
            }
        }
        return result
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
