import Foundation

/// Parses schema.org durations such as "PT1H30M", "P0DT0H25M", "PT0.5H" or
/// "P0Y0M0DT0H35M0.000S". Sites also write plain text ("20 mins"), which falls
/// back to `DurationExtractor`.
public enum ISO8601Duration {
    private static let regex = NSRegularExpression(compiling:
        #"^P(?:(\d+(?:[.,]\d+)?)Y)?(?:(\d+(?:[.,]\d+)?)M)?(?:(\d+(?:[.,]\d+)?)W)?(?:(\d+(?:[.,]\d+)?)D)?"#
        + #"(?:T(?:(\d+(?:[.,]\d+)?)H)?(?:(\d+(?:[.,]\d+)?)M)?(?:(\d+(?:[.,]\d+)?)S)?)?$"#)

    /// Seconds in each captured component: years, months, weeks, days, hours, minutes, seconds.
    private static let multipliers: [Double] = [365 * 86_400, 30 * 86_400, 7 * 86_400, 86_400, 3600, 60, 1]

    /// Seconds for an ISO 8601 duration, nil when the text is not one.
    public static func seconds(from text: String) -> TimeInterval? {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.count > 1, compact.uppercased().hasPrefix("P"),
              let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) else {
            return nil
        }
        var total: Double = 0
        var sawComponent = false
        for (index, multiplier) in multipliers.enumerated() {
            guard let value = match.group(index + 1, in: compact) else { continue }
            sawComponent = true
            total += (Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0) * multiplier
        }
        return sawComponent ? total : nil
    }

    /// Reads a recipe time written either as ISO 8601 or as plain text.
    /// Zero and unreadable values become nil, because sites use "PT0S" for "unknown".
    public static func recipeTime(from text: String) -> TimeInterval? {
        let value = seconds(from: text) ?? DurationExtractor.extract(from: text).first?.upperBound
        guard let value, value > 0 else { return nil }
        return value
    }
}
