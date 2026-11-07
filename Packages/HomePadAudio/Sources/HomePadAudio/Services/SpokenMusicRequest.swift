import Foundation
import HomePadCore

/// Splits a spoken request such as "Taylor Swift in the kitchen" into what to play
/// ("Taylor Swift") and the speaker it names. The speaker must match by its whole
/// name or every word, so song titles like "Born on the Bayou" stay intact.
struct SpokenMusicRequest: Equatable {
    var query: String
    var speakerID: AudioOutput.ID?

    init(_ text: String, speakers: [AudioOutput]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        for separator in [" in the ", " on the ", " in ", " on "] {
            guard let range = trimmed.range(of: separator, options: [.backwards, .caseInsensitive]) else { continue }
            let head = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let tail = String(trimmed[range.upperBound...])
            guard !head.isEmpty, let speaker = RemotePlayerMapper.find(tail, in: speakers, strict: true) else { continue }
            query = head
            speakerID = speaker.id
            return
        }
    }
}
