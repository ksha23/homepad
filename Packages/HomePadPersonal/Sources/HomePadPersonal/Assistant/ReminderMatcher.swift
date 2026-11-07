import Foundation

/// Finds the reminder someone means from loosely spoken words ("the milk").
enum ReminderMatcher {
    /// Exact match first, then containment either way, then the most shared words.
    static func bestMatch(for spoken: String, in items: [ReminderItem]) -> ReminderItem? {
        let needle = normalize(spoken)
        guard !needle.isEmpty else { return nil }
        let open = items.filter { !$0.isCompleted }
        if let exact = open.first(where: { normalize($0.title) == needle }) { return exact }
        if let contained = open.first(where: { normalize($0.title).contains(needle) || needle.contains(normalize($0.title)) }) {
            return contained
        }
        let words = Set(needle.split(separator: " "))
        let scored = open.map { item in (item, Set(normalize(item.title).split(separator: " ")).intersection(words).count) }
        return scored.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words = lowered.split { !$0.isLetter && !$0.isNumber }.filter { !["the", "a", "an", "some"].contains($0) }
        return words.joined(separator: " ")
    }
}
