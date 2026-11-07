import Foundation

extension FlyerEventExtractor {
    /// How flyers, invitations and letters write dates, titles and places.
    enum Patterns {
        // MARK: What a date match wrote

        private static let time = regex(
            #"\b\d{1,2}:\d{2}\b|\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)(?![a-z])|\bnoon\b|\bmidnight\b|(?:\bat|@)\s*\d{1,2}\b|\bfrom\s+\d{1,2}\b"#)
        private static let month = regex(
            #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b|\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#)
        private static let year = regex(#"\b(?:19|20)\d{2}\b|\b\d{1,2}/\d{1,2}/\d{2,4}\b"#)
        private static let weekdayName = regex(
            #"\b(sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat)\b"#)

        /// True when the text has a clock time: "10 AM", "6:30", "noon", "at 7".
        static func hasTime(_ text: String) -> Bool { matches(time, text) }

        /// True when the text names a month or writes a day as "3/14".
        static func hasMonthOrNumericDate(_ text: String) -> Bool { matches(month, text) }

        static func hasYear(_ text: String) -> Bool { matches(year, text) }

        /// The weekday the text names, 1 for Sunday to 7 for Saturday, as `Calendar` counts.
        static func weekday(in text: String) -> Int? {
            guard let match = weekdayName.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            let order = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            return order.firstIndex(of: String(text[range].prefix(3))).map { $0 + 1 }
        }

        /// 0 for "today" or "tonight", 1 for "tomorrow".
        static func relativeDay(in text: String) -> Int? {
            if text.contains("tomorrow") { return 1 }
            if text.contains("today") || text.contains("tonight") { return 0 }
            return nil
        }

        // MARK: Kinds of lines

        private static let deadline = regex(
            #"\b(?:rsvp|r\.s\.v\.p|due|deadline|reply by|respond by|register by|sign up by|last day to|turn in|return (?:it |them |the form )?by)\b"#)
        private static let leadIns = [
            regex(#"^\s*(?:you'?re|you are|you’re)\s+(?:cordially\s+)?invited(?:\s+to)?\b[\s!.:,]*"#),
            regex(#"^\s*(?:please\s+)?(?:come\s+)?join\s+us\s+(?:for|at|to)\b\s*"#),
            regex(#"^\s*save\s+the\s+date(?:\s+for)?\b[\s!.:,]*"#),
            regex(#"^\s*(?:come\s+to|celebrate)\s+"#),
        ]
        private static let salutation = regex(#"^\s*(?:dear|hello|hi|hey|greetings|thank you|thanks|sincerely|best|regards|love)\b"#)
        static let label = regex(#"^\s*(what|event|where|location|place|venue|address|when|date|time)\s*[:\-–]\s*(.*)$"#)
        private static let placeAfterDate = regex(#"^[\s,\-–—·|]*(?:at|in|@)\s+(.+?)[\s.,;!]*$"#)

        /// A deadline rather than an event: "RSVP by", "slips are due".
        static func isDeadline(_ text: String) -> Bool { matches(deadline, text) }

        /// "Dear Families," and "Thank you," start and end letters, never name events.
        static func isSalutation(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return matches(salutation, trimmed) || (trimmed.hasSuffix(",") && trimmed.split(separator: " ").count <= 4)
        }

        /// The line without an invitation's lead-in: "You're invited to Maya's
        /// party" is "Maya's party". Nil when nothing is left ("You're Invited!").
        static func withoutLeadIn(_ line: String) -> String? {
            var text = line
            for leadIn in leadIns {
                text = leadIn.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
            let trimmed = trim(text)
            return trimmed.isEmpty ? nil : trimmed
        }

        // MARK: Titles

        /// Words that only frame a date: "When:", "on", "from", "Doors".
        private static let fillers: Set<String> = [
            "when", "date", "time", "day", "on", "at", "from", "the", "a", "an", "and", "until", "to", "by", "is", "are",
            "starts", "begins", "doors", "open", "opens", "rsvp", "please", "join", "us", "every", "each", "am", "pm",
        ]
        /// Words between a title and its date: "Our trip will be on", "The fair is from".
        private static let connectors: Set<String> = [
            "on", "at", "is", "are", "be", "will", "from", "by", "this", "next", "starts", "start", "begins", "begin",
            "starting", "due", "until", "through", "thru", "and", "or", "held", "scheduled", "for", "when", "date", "time",
        ]
        private static let leadingLabel = regex(#"^\s*(?:when|date|time|what|event|day)\s*[:\-–]\s*"#)

        /// The words beside a date without labels and connecting words, or nil.
        static func cleanTitle(_ text: String) -> String? {
            var words = trim(leadingLabel.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""))
                .split(whereSeparator: \.isWhitespace).map(String.init)
            while let last = words.last, connectors.contains(trim(last).lowercased()) || trim(last).isEmpty { words.removeLast() }
            while let first = words.first, trim(first).isEmpty { words.removeFirst() }
            if words.first?.lowercased() == "our" { words.removeFirst() }
            let title = trim(words.joined(separator: " "))
            return title.isEmpty ? nil : title
        }

        /// True when the words name something beyond framing a date.
        static func isMeaningful(_ text: String) -> Bool {
            guard text.filter(\.isLetter).count >= 3 else { return false }
            return text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).contains { !fillers.contains(String($0)) }
        }

        /// Shouted flyer type in title case ("SPRING BAKE SALE" is "Spring Bake
        /// Sale"), and anything else with a capital first letter.
        static func displayCase(_ text: String) -> String {
            let trimmed = trim(text)
            guard trimmed.contains(where: \.isLetter), !trimmed.contains(where: \.isLowercase) else {
                return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
            }
            let minor: Set<String> = ["a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to", "with"]
            let acronyms: Set<String> = ["PTA", "PTO", "BBQ", "YMCA", "DJ", "USA", "5K", "10K"]
            return trimmed.split(separator: " ").enumerated().map { index, word in
                if acronyms.contains(String(word)) { return String(word) }
                let lower = word.lowercased()
                if index > 0, minor.contains(lower) { return lower }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }.joined(separator: " ")
        }

        /// What an event is likely called: a line with one of these is a better headline.
        private static let eventWords: Set<String> = [
            "party", "birthday", "sale", "fair", "festival", "night", "concert", "recital", "meeting", "game", "match",
            "tournament", "practice", "trip", "picnic", "potluck", "dinner", "lunch", "breakfast", "brunch", "celebration",
            "ceremony", "show", "play", "workshop", "class", "camp", "conference", "fundraiser", "carnival", "auction",
            "social", "reunion", "shower", "wedding", "house", "cleanup", "drive", "walk", "run", "race", "market", "tour",
            "day", "service", "gala", "dance", "performance", "exhibit", "screening", "graduation", "orientation",
            "assembly", "parade", "bbq", "barbecue", "cookout", "rally", "club", "storytime", "sleepover", "playdate",
        ]

        static func hasEventWord(_ text: String) -> Bool {
            text.lowercased().split(whereSeparator: { !$0.isLetter }).contains { eventWords.contains(String($0)) }
        }

        /// All capitals, or every longer word capitalized, as headlines are set.
        static func isHeadingCase(_ text: String) -> Bool {
            let letters = text.filter(\.isLetter)
            if letters.count >= 2, !letters.contains(where: \.isLowercase) { return true }
            let long = text.split(separator: " ").filter { $0.count >= 4 }
            return !long.isEmpty && long.allSatisfy { $0.first?.isUppercase == true }
        }

        // MARK: Places

        private static let placeWords: Set<String> = [
            "school", "elementary", "gym", "park", "pavilion", "library", "hall", "center", "centre", "church", "room",
            "cafeteria", "auditorium", "field", "stadium", "theater", "theatre", "museum", "zoo", "restaurant", "studio",
            "arena", "club", "campus", "pool", "rink", "court", "community", "lodge", "barn", "farm", "garden", "beach",
        ]

        /// "at Westside Park" or "in the auditorium" after a date, as the place.
        static func place(in text: String) -> String? {
            guard let match = placeAfterDate.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            let place = trim(String(text[range]))
            return isMeaningful(place) ? place : nil
        }

        /// A short line that could name a place: no sentence, no exclamation.
        static func isPlaceName(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let words = trimmed.split(separator: " ")
            return (1...8).contains(words.count) && trimmed.contains(where: \.isLetter)
                && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?") && !trimmed.hasSuffix(".") && label.firstMatch(
                    in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil
        }

        static func hasPlaceWord(_ text: String) -> Bool {
            text.lowercased().split(whereSeparator: { !$0.isLetter }).contains { placeWords.contains(String($0)) }
        }

        // MARK: Helpers

        private static func regex(_ pattern: String) -> NSRegularExpression {
            do {
                return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            } catch {
                preconditionFailure("Invalid regular expression \(pattern): \(error)")
            }
        }

        private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }

        /// Spaces and the punctuation flyers put between a label, a title and a date.
        static func trim(_ text: String) -> String {
            text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—,·|@(*•▪︎")))
        }
    }
}
