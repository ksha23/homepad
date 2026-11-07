import Foundation
import SwiftUI

/// Answers mark their key facts in Markdown bold ("**1842**"). This reads them
/// for the big answer type, and takes the marks out where they must not show
/// or be heard: speech, Siri and Handoff.
enum AnswerMarkdown {
    /// The answer with its bold runs. Inline Markdown only, so a stray "#" or "-"
    /// stays text and never turns into a heading or a list. A bold run still
    /// streaming in shows plain until its closing "**" arrives, instead of
    /// flashing the asterisks.
    static func attributed(_ text: String) -> AttributedString {
        let closed = withoutOpenMark(text)
        if let parsed = try? AttributedString(markdown: closed, options: options) { return parsed }
        return AttributedString(plain(text))
    }

    /// The answer with its bold runs drawn in `boldFont`. Under a font with a
    /// weight of its own, such as the answer's medium, SwiftUI draws Markdown
    /// bold at that weight, so the bold runs carry their own font.
    static func attributed(_ text: String, boldFont: Font) -> AttributedString {
        var result = attributed(text)
        for run in result.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            result[run.range].swiftUI.font = boldFont
        }
        return result
    }

    /// The answer as plain words, for speech and for text shown outside HomePad.
    static func plain(_ text: String) -> String {
        let parsed = (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? text
        // A sentence cut out of a bold run ("**Dr." and "Smith**") keeps marks the
        // parser left alone. Spoken, they would be read out.
        return parsed.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
    }

    private static let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible
    )

    /// Drops the last "**" when it has no partner yet.
    private static func withoutOpenMark(_ text: String) -> String {
        let marks = text.components(separatedBy: "**").count - 1
        guard marks % 2 == 1, let last = text.range(of: "**", options: .backwards) else { return text }
        return text.replacingCharacters(in: last, with: "")
    }
}
