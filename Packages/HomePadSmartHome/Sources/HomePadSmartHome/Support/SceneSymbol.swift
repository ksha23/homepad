import Foundation

/// Picks an SF Symbol for a scene from its Material Design icon (Home Assistant)
/// or its name (any backend). Returns nil when nothing fits.
enum SceneSymbol {
    private static let keywords: [(words: [String], symbol: String)] = [
        (["night", "sleep", "bed", "moon"], "moon.stars.fill"),
        (["morning", "sunrise", "wake", "sunny"], "sun.horizon.fill"),
        (["away", "leave", "exit", "depart", "run", "walk"], "figure.walk.departure"),
        (["arrive", "home", "welcome", "house"], "house.fill"),
        (["movie", "tv", "television", "theater", "theatre"], "tv.fill"),
        (["dinner", "food", "silverware", "kitchen", "cook"], "fork.knife"),
        (["party", "music"], "party.popper.fill"),
        (["read", "book"], "book.fill"),
        (["relax", "candle", "sofa", "couch"], "sofa.fill"),
        (["work", "focus", "desk", "office"], "desktopcomputer"),
        (["bright", "lightbulb", "lights"], "lightbulb.fill"),
    ]

    static func symbol(icon: String?, name: String) -> String? {
        let haystacks = [icon?.replacingOccurrences(of: "mdi:", with: ""), name].compactMap { $0?.lowercased() }
        for haystack in haystacks {
            if let match = keywords.first(where: { entry in entry.words.contains { haystack.contains($0) } }) {
                return match.symbol
            }
        }
        return nil
    }
}
