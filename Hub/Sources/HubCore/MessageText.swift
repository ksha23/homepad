import Foundation

/// Recent macOS versions leave `message.text` empty for many messages and put
/// the text in `attributedBody`, an `NSAttributedString` archived with the
/// legacy typedstream format. `NSUnarchiver` still reads it.
enum MessageText {
    static func resolve(text: String?, attributedBody: Data?) -> String {
        if let text, !text.isEmpty { return clean(text) }
        guard let attributedBody, let decoded = decode(attributedBody) else { return "" }
        return clean(decoded)
    }

    private static func decode(_ data: Data) -> String? {
        guard let archived = NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString else { return nil }
        return archived.string
    }

    /// Drops the object replacement character that marks an inline attachment.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
