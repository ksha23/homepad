import Foundation

/// Reads a short spoken reply as yes, no, or neither.
enum YesNoClassifier {
    private static let yes: Set<String> = [
        "yes", "yeah", "yep", "yup", "sure", "ok", "okay", "confirm", "confirmed", "affirmative",
        "do it", "go ahead", "please do", "absolutely", "of course", "correct", "right",
    ]
    private static let no: Set<String> = [
        "no", "nope", "nah", "cancel", "stop", "don't", "do not", "never mind", "nevermind",
        "negative", "wait", "not now", "abort",
    ]

    /// Negative phrases win over positive ones ("no, don't do it" is no).
    static func classify(_ text: String) -> Bool? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "' ")).inverted)
            .joined(separator: " ")
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 8 else { return nil }
        let phrases = Set(words + zip(words, words.dropFirst()).map { "\($0) \($1)" })
        if !phrases.isDisjoint(with: no) { return false }
        if !phrases.isDisjoint(with: yes) { return true }
        return nil
    }
}
