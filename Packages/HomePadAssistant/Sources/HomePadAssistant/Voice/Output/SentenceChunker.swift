import Foundation

/// Cuts streamed answer text into whole sentences so speech can start before
/// the answer is complete. Decimals like "3.5" and very short fragments are not split.
struct SentenceChunker {
    /// Fragments shorter than this wait for more text.
    var minimumLength = 12
    private var buffer = ""

    /// Adds streamed text and returns any sentences that are now complete.
    mutating func append(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        var searchStart = buffer.startIndex
        while let boundary = nextBoundary(from: searchStart) {
            let sentence = buffer[..<boundary].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= minimumLength {
                sentences.append(sentence)
                buffer = String(buffer[boundary...])
                searchStart = buffer.startIndex
            } else {
                searchStart = boundary
            }
        }
        return sentences
    }

    /// Returns whatever is left when the answer ends.
    mutating func flush() -> String? {
        defer { buffer = "" }
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// The index just after sentence punctuation that is followed by whitespace.
    private func nextBoundary(from start: String.Index) -> String.Index? {
        var index = start
        while index < buffer.endIndex {
            let character = buffer[index]
            let next = buffer.index(after: index)
            if character == "\n" { return next }
            if ".!?".contains(character), next < buffer.endIndex, buffer[next].isWhitespace { return next }
            index = next
        }
        return nil
    }
}
