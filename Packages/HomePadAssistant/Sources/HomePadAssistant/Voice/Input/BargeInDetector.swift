import Foundation

/// Hears "stop" while HomePad is talking. The microphone also picks up
/// HomePad's own voice, so a stop word only counts when the sentence being
/// spoken does not contain it.
enum BargeInDetector {
    static let stopWords: Set<String> = ["stop", "cancel", "quiet", "enough", "nevermind", "shush", "silence"]

    static func isStopCommand(heard: String, speaking: String) -> Bool {
        let spoken = Set(words(speaking))
        let recent = words(heard).suffix(3)
        return recent.contains { stopWords.contains($0) && !spoken.contains($0) }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "never mind", with: "nevermind")
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }
}
