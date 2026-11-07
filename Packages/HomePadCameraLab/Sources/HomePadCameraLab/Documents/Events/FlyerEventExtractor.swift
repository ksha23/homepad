import Foundation

/// Finds events in text read from a flyer, an invitation or a school letter,
/// entirely on this iPad.
///
/// `NSDataDetector` finds the dates, times, ranges and street addresses. It
/// picks years and fills in missing days inconsistently, so each date is
/// read again from what the page wrote: a date without a year is the next
/// one from today on (the one whose weekday matches, when the page names
/// the weekday), a weekday alone is the next such day, and a time alone
/// belongs to the date above it. The lines around a date give the event its
/// title and place: the rest of its line ("Picture Day: Sept 17"), a
/// "What:" or "Where:" label, an address with the place named above it, or
/// else the flyer's headline.
struct FlyerEventExtractor {
    /// The day "next" counts from.
    var now = Date()
    var calendar = Calendar.current

    func events(in text: String) -> [ScannedEvent] {
        let page = Page(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        let found = page.detect(calendar: calendar)
        let mentions = found.dates.compactMap { mention($0, on: page) }
        let drafts = group(mentions)
        let headline = Self.headline(on: page, before: drafts.first?.line ?? page.lines.count, found: found)
        let labels = Self.labels(on: page)
        var events: [ScannedEvent] = []
        for draft in drafts {
            guard let event = event(from: draft, on: page, found: found, headline: headline, labels: labels) else { continue }
            if !events.contains(where: { $0.title == event.title && $0.start == event.start }) { events.append(event) }
        }
        return events.sorted { $0.start < $1.start }
    }

    // MARK: Dates and times

    /// A date or a time the detector found, read again from what the page wrote.
    struct Mention {
        var range: NSRange
        var line: Int
        /// Year, month and day, when the page gave a day.
        var day: DateComponents?
        var time: (hour: Int, minute: Int)?
        /// A range's length: "10 AM - 2 PM", or "October 22-23".
        var duration: TimeInterval
    }

    private func mention(_ match: NSTextCheckingResult, on page: Page) -> Mention? {
        guard let date = match.date else { return nil }
        let written = page.substring(match.range).lowercased()
        let detected = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let weekday = Patterns.weekday(in: written)
        var day: DateComponents?
        if Patterns.hasMonthOrNumericDate(written), let month = detected.month, let dayOfMonth = detected.day {
            day = Patterns.hasYear(written)
                ? DateComponents(year: detected.year, month: month, day: dayOfMonth)
                : nextDate(month: month, day: dayOfMonth, weekday: weekday)
        } else if let offset = Patterns.relativeDay(in: written) {
            day = dayComponents(calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        } else if let weekday {
            day = nextWeekday(weekday)
        }
        let time = Patterns.hasTime(written) ? (detected.hour ?? 0, detected.minute ?? 0) : nil
        guard day != nil || time != nil else { return nil }
        return Mention(range: match.range, line: page.line(at: match.range.location), day: day, time: time, duration: match.duration)
    }

    /// The next month and day from today on. When the page names the weekday,
    /// the next year where that day falls on it, if one is near.
    private func nextDate(month: Int, day: Int, weekday: Int?) -> DateComponents? {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: now)
        let upcoming = (year...(year + 2)).compactMap { candidate -> Date? in
            guard let date = calendar.date(from: DateComponents(year: candidate, month: month, day: day)),
                  calendar.component(.day, from: date) == day, date >= today else { return nil }
            return date
        }
        let chosen = weekday.flatMap { wanted in upcoming.first { calendar.component(.weekday, from: $0) == wanted } } ?? upcoming.first
        return chosen.map(dayComponents)
    }

    private func nextWeekday(_ weekday: Int) -> DateComponents {
        let today = calendar.startOfDay(for: now)
        let ahead = (weekday - calendar.component(.weekday, from: today) + 7) % 7
        return dayComponents(calendar.date(byAdding: .day, value: ahead, to: today) ?? today)
    }

    private func dayComponents(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    // MARK: Grouping

    /// One event before its title and place are found: a day, with the times
    /// written with it or on the lines just under it.
    struct Draft {
        var mention: Mention
        var day: DateComponents
        var line: Int
        var lastLine: Int
        var start: (hour: Int, minute: Int)?
        var end: (hour: Int, minute: Int)?
        var duration: TimeInterval
    }

    /// How far below its date a time may stand and still belong to it.
    private static let timeReach = 2

    private func group(_ mentions: [Mention]) -> [Draft] {
        var drafts: [Draft] = []
        var pendingTime: Mention?
        for mention in mentions {
            if let day = mention.day {
                var draft = Draft(mention: mention, day: day, line: mention.line, lastLine: mention.line,
                                  start: mention.time, duration: mention.duration)
                // A time written just above its date ("6:30 PM" then "Friday, Nov 13").
                if draft.start == nil, let time = pendingTime, mention.line - time.line <= Self.timeReach {
                    draft.start = time.time
                    draft.duration = time.duration
                }
                pendingTime = nil
                drafts.append(draft)
            } else if let time = mention.time {
                guard var last = drafts.last, mention.line - last.lastLine <= Self.timeReach else {
                    pendingTime = mention
                    continue
                }
                if last.start == nil {
                    last.start = time
                    last.duration = mention.duration
                } else if last.end == nil, last.duration == 0, let start = last.start, (time.hour, time.minute) > (start.hour, start.minute) {
                    // "leaves at 9:15 AM and returns by 2:30 PM".
                    last.end = time
                }
                last.lastLine = mention.line
                drafts[drafts.count - 1] = last
            }
        }
        return drafts
    }

    // MARK: Events

    private func event(from draft: Draft, on page: Page, found: Detected, headline: String?, labels: Labels) -> ScannedEvent? {
        guard let firstDay = calendar.date(from: draft.day) else { return nil }
        let sentence = page.sentence(around: draft.mention.range, otherMentions: found.dates.map(\.range))
        let isDeadline = Patterns.isDeadline(sentence.whole)
        let own = Self.title(before: sentence.before, after: sentence.after)

        let title: String
        if isDeadline {
            title = Self.deadlineTitle(sentence.whole, own: own, headline: headline ?? labels.what)
        } else {
            title = own ?? labels.what ?? headline ?? "Event"
        }

        var start: Date
        var end: Date
        let isAllDay = draft.start == nil
        if let time = draft.start {
            start = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: firstDay) ?? firstDay
            if draft.duration > 0 {
                end = start.addingTimeInterval(draft.duration)
            } else if let finish = draft.end {
                end = calendar.date(bySettingHour: finish.hour, minute: finish.minute, second: 0, of: firstDay) ?? start
            } else {
                end = start.addingTimeInterval(Self.defaultLength)
            }
        } else {
            // "October 22-23" is a day plus a day's duration: an event over both days.
            start = firstDay
            let extraDays = Int((draft.duration / 86_400).rounded())
            end = calendar.date(byAdding: .day, value: max(0, extraDays), to: firstDay) ?? firstDay
        }
        if end < start { end = start }

        let location = isDeadline ? "" : (Self.place(after: sentence.after) ?? labels.where_ ?? address(near: draft, on: page, found: found, headline: headline) ?? "")
        return ScannedEvent(title: title, start: start, end: end, isAllDay: isAllDay, location: location,
                            isSelected: !isDeadline, source: page.lines[draft.line].text)
    }

    /// An hour, like the assistant's events and Calendar's new ones, when the page gives no end.
    static let defaultLength: TimeInterval = 3600

    /// A street address at or after the event's lines, with the place named
    /// on the line above it when there is one ("Lincoln Elementary School Gym").
    private func address(near draft: Draft, on page: Page, found: Detected, headline: String?) -> String? {
        let candidates = found.addresses.filter { $0.line >= draft.line }
        guard let address = candidates.first ?? (found.addresses.count == 1 ? found.addresses.first : nil) else {
            return placeLine(after: draft, on: page, found: found, headline: headline)
        }
        let text = page.substring(address.range).trimmingCharacters(in: .whitespacesAndNewlines)
        let above = address.line - 1
        guard above > draft.lastLine, !found.linesWithMatches.contains(above),
              Patterns.isPlaceName(page.lines[above].text), page.lines[above].text != headline else { return text }
        return "\(page.lines[above].text.trimmingCharacters(in: .whitespaces)), \(text)"
    }

    /// A line just under the date and time that names a place but no street,
    /// such as "Westside Park Pavilion".
    private func placeLine(after draft: Draft, on page: Page, found: Detected, headline: String?) -> String? {
        let following = (draft.lastLine + 1)..<min(page.lines.count, draft.lastLine + 1 + Self.timeReach)
        return following.lazy
            .filter { !found.linesWithMatches.contains($0) }
            .map { page.lines[$0].text.trimmingCharacters(in: .whitespaces) }
            .first { Patterns.isPlaceName($0) && Patterns.hasPlaceWord($0) && $0 != headline }
    }

    // MARK: Titles

    /// The words beside a date on its line or in its sentence, when they name
    /// something: "Picture Day" in "Picture Day: Thursday, September 17".
    static func title(before: String, after: String) -> String? {
        let leading = Patterns.cleanTitle(before)
        if let leading, Patterns.isMeaningful(leading) { return Patterns.displayCase(leading) }
        guard Patterns.place(in: after) == nil, let trailing = Patterns.cleanTitle(after), Patterns.isMeaningful(trailing) else { return nil }
        return Patterns.displayCase(trailing)
    }

    /// "RSVP for Maya's 7th Birthday Party", or "Permission slips due".
    static func deadlineTitle(_ sentence: String, own: String?, headline: String?) -> String {
        if sentence.lowercased().contains("rsvp") { return headline.map { "RSVP for \($0)" } ?? "RSVP" }
        if let own { return own.lowercased().hasSuffix("due") ? own : own + " due" }
        return headline.map { "Deadline for \($0)" } ?? "Deadline"
    }

    /// The place after a date: "in the auditorium" in "Winter Concert Dec 10 at 7pm in the auditorium".
    static func place(after: String) -> String? {
        Patterns.place(in: after).map(Patterns.displayCase)
    }

    /// The flyer's headline: the line above the first date most like an
    /// event's name. "SPRING BAKE SALE" beats "LINCOLN ELEMENTARY PTA", and
    /// "You're Invited!" says nothing, so it is skipped.
    static func headline(on page: Page, before firstDateLine: Int, found: Detected) -> String? {
        var best: (score: Double, text: String)?
        for index in 0..<min(firstDateLine, page.lines.count) where !found.linesWithMatches.contains(index) {
            let raw = page.lines[index].text
            guard Labels.label(in: raw) == nil, !Patterns.isSalutation(raw),
                  let text = Patterns.withoutLeadIn(raw), Patterns.isMeaningful(text) else { continue }
            let words = text.split(separator: " ")
            guard words.count <= 12 else { continue }
            var score = -0.25 * Double(index)
            if Patterns.hasEventWord(text) { score += 3 }
            if Patterns.isHeadingCase(text) { score += 1 }
            if (2...7).contains(words.count) { score += 1 }
            if best == nil || score > best!.score { best = (score, Patterns.displayCase(text)) }
        }
        return best?.text
    }

    // MARK: Labels

    /// "What:" and "Where:" lines, common on invitations.
    struct Labels {
        var what: String?
        var where_: String?

        static func label(in line: String) -> (name: String, value: String)? {
            guard let match = Patterns.label.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line), let value = Range(match.range(at: 2), in: line) else { return nil }
            return (line[name].lowercased(), line[value].trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func labels(on page: Page) -> Labels {
        var labels = Labels()
        for line in page.lines {
            guard let (name, value) = Labels.label(in: line.text), !value.isEmpty else { continue }
            switch name {
            case "what", "event": if labels.what == nil { labels.what = Patterns.displayCase(value) }
            case "where", "location", "place", "venue", "address": if labels.where_ == nil { labels.where_ = value }
            default: break
            }
        }
        return labels
    }
}

// MARK: - The page

extension FlyerEventExtractor {
    /// The text with its lines and where each starts, in UTF-16 offsets as
    /// `NSDataDetector` reports them.
    struct Page {
        struct Line {
            var text: String
            var range: NSRange
        }

        let text: String
        let lines: [Line]
        private let nsText: NSString

        init(_ text: String) {
            self.text = text
            nsText = text as NSString
            var lines: [Line] = []
            var location = 0
            for piece in text.components(separatedBy: "\n") {
                let length = (piece as NSString).length
                lines.append(Line(text: piece, range: NSRange(location: location, length: length)))
                location += length + 1
            }
            self.lines = lines
        }

        func substring(_ range: NSRange) -> String {
            nsText.substring(with: range)
        }

        func line(at location: Int) -> Int {
            lines.lastIndex { $0.range.location <= location } ?? 0
        }

        /// The sentence holding a date, split around it, with other dates and
        /// times taken out. A short line is its own sentence, and a letter's
        /// long line is cut at ". ", "! " and "? ".
        func sentence(around range: NSRange, otherMentions: [NSRange]) -> (before: String, after: String, whole: String) {
            let line = lines[line(at: range.location)]
            let lineText = line.text as NSString
            var start = range.location - line.range.location
            let end = min(lineText.length, start + range.length)
            // The detector takes "night" in "Movie night Friday at 6" as part
            // of the date. It belongs to the title.
            if start > 0, let partOfDay = Self.partOfDay?.firstMatch(in: substring(range), range: NSRange(location: 0, length: range.length)) {
                start += partOfDay.range.length
            }
            var before = lineText.substring(to: max(0, start))
            var after = lineText.substring(from: end)
            if let cut = before.range(of: #"[.!?]\s"#, options: [.regularExpression, .backwards]) {
                before = String(before[cut.upperBound...])
            }
            if let cut = after.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
                after = String(after[..<cut.lowerBound])
            }
            for other in otherMentions where other != range {
                after = after.replacingOccurrences(of: substring(other), with: " ")
                before = before.replacingOccurrences(of: substring(other), with: " ")
            }
            return (before, after, before + " " + after)
        }

        /// A part of the day at the start of a date match: "Night Friday, Nov 13".
        private static let partOfDay = try? NSRegularExpression(pattern: #"^(?:night|morning|evening|afternoon)\b"#, options: [.caseInsensitive])

        /// "due" before a date, as in "Permission slips are due Monday, October 5".
        private static let due = try? NSRegularExpression(pattern: #"\bdue\b"#, options: [.caseInsensitive])

        func detect(calendar: Calendar) -> Detected {
            let types: NSTextCheckingResult.CheckingType = [.date, .address, .phoneNumber, .link]
            guard let detector = try? NSDataDetector(types: types.rawValue) else { return Detected() }
            // The detector finds no date after the word "due" (measured on
            // macOS 27, and the school letter test checks it on iOS). "by " has
            // the same length, so the dates it then finds sit at the same
            // offsets in the page's own text, which still says "due" for the
            // deadline check.
            let range = NSRange(location: 0, length: nsText.length)
            let searched = Self.due?.stringByReplacingMatches(in: text, range: range, withTemplate: "by ") ?? text
            var found = Detected()
            for match in detector.matches(in: searched, range: range) {
                let lineIndex = line(at: match.range.location)
                found.linesWithMatches.insert(lineIndex)
                switch match.resultType {
                case .date: found.dates.append(match)
                case .address: found.addresses.append(Located(range: match.range, line: lineIndex))
                default: break
                }
            }
            return found
        }
    }

    struct Located {
        var range: NSRange
        var line: Int
    }

    /// What the detector found on the page.
    struct Detected {
        var dates: [NSTextCheckingResult] = []
        var addresses: [Located] = []
        /// Lines with a date, an address, a phone number or a link, which are never a headline.
        var linesWithMatches: Set<Int> = []
    }
}
