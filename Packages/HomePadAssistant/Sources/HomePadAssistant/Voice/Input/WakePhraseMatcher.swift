import Foundation

/// Finds the wake phrase in a running transcript, tolerating how recognizers
/// split or mishear it ("hey home pad", "hay homepad"), and returns what was
/// said after it. It runs on every partial transcript while HomePad waits for
/// the phrase, so it skips work that cannot match.
enum WakePhraseMatcher {
    /// The words after the phrase (possibly empty), or nil when the phrase was not heard.
    static func remainder(after phrase: String, in transcript: String) -> String? {
        let target = squash(phrase)
        guard !target.isEmpty else { return nil }
        let words = transcript.split(whereSeparator: \.isWhitespace).map(String.init)
        let normalized = words.map(squash)
        let tolerance = target.count >= 8 ? 2 : target.count >= 4 ? 1 : 0

        for start in normalized.indices {
            var joined = ""
            for end in start..<normalized.count {
                joined += normalized[end]
                if joined.count > target.count + tolerance { break }
                // The edit distance is at least the difference in length, so
                // a span still too short cannot match yet.
                if joined.count + tolerance < target.count { continue }
                if editDistance(joined, target) <= tolerance {
                    let rest = words[(end + 1)...].joined(separator: " ")
                    return rest.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
                }
            }
        }
        return nil
    }

    /// Lowercase letters and digits only.
    static func squash(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    /// Levenshtein distance for short strings.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
