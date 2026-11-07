import Foundation

public extension Date {
    /// The time for big clock faces: "4:11" or "16:11", following the locale's
    /// 12 or 24 hour preference, without AM or PM and without a leading zero.
    ///
    ///     TimelineView(.everyMinute) { context in
    ///         Text(context.date.clockTime()).font(.display(200))
    ///     }
    func clockTime(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let template = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "h:mm"
        // Drop the day period ("a", "b", "B") and the spaces around it.
        let pattern = template
            .replacingOccurrences(of: "[abB]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{202F}\u{00A0}")))
        formatter.dateFormat = pattern
        return formatter.string(from: self)
    }
}
