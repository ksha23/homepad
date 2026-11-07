import Foundation

/// A run of step text: plain words, an ingredient amount (shown in orange) or a
/// cooking time (shown as a tappable timer).
public struct StepSegment: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case text
        case amount
        case duration(DetectedDuration)
    }

    public var text: String
    public var kind: Kind
}

/// Splits a cooking step into segments, scaling and converting the amounts it mentions.
public enum StepTextAnalyzer {
    /// Segments in reading order. Joining their `text` gives the adjusted step.
    public static func segments(for step: String, adjustment: AmountAdjustment = AmountAdjustment()) -> [StepSegment] {
        let durations = DurationExtractor.extract(from: step)
        let amounts = QuantityParser.findMeasured(in: step).filter { amount in
            !durations.contains { $0.range.overlaps(amount.range) }
        }

        enum Span {
            case amount(IngredientAmount, Range<String.Index>), duration(DetectedDuration)

            var start: String.Index {
                switch self {
                case .amount(_, let range): range.lowerBound
                case .duration(let duration): duration.range.lowerBound
                }
            }
        }
        let spans: [Span] = (amounts.map { .amount($0.amount, $0.range) } + durations.map { .duration($0) })
            .sorted { $0.start < $1.start }

        var segments: [StepSegment] = []
        var cursor = step.startIndex
        for span in spans {
            switch span {
            case .amount(let amount, let range):
                guard range.lowerBound >= cursor else { continue }
                appendText(step[cursor..<range.lowerBound], to: &segments)
                let text = adjustment.isIdentity
                    ? String(step[range])
                    : QuantityFormatter.string(for: RecipeScaler.adjust(amount, with: adjustment))
                segments.append(StepSegment(text: text, kind: .amount))
                cursor = range.upperBound
            case .duration(let duration):
                guard duration.range.lowerBound >= cursor else { continue }
                appendText(step[cursor..<duration.range.lowerBound], to: &segments)
                segments.append(StepSegment(text: duration.text, kind: .duration(duration)))
                cursor = duration.range.upperBound
            }
        }
        appendText(step[cursor...], to: &segments)
        return segments
    }

    /// The step as plain text with amounts adjusted, for reading aloud.
    public static func plainText(for step: String, adjustment: AmountAdjustment) -> String {
        segments(for: step, adjustment: adjustment).map(\.text).joined()
    }

    private static func appendText(_ text: Substring, to segments: inout [StepSegment]) {
        guard !text.isEmpty else { return }
        segments.append(StepSegment(text: String(text), kind: .text))
    }
}
