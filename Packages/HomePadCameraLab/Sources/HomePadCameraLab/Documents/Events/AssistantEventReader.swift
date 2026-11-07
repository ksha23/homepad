import Foundation
import HomePadCore

/// Reads events from recognized text with the household's AI provider, for
/// pages the on-device reading gets wrong. Only offered when an assistant is
/// set up, and only when the person asks.
///
/// The provider gets the prompt below with the recognized text and today's
/// date, as a self-contained text task (`AssistantRequest.textTask`): never
/// the photo, no tools, no chat history and nothing about the household.
@MainActor
enum AssistantEventReader {
    static func read(_ text: String, with assistant: any AssistantService, now: Date = Date(),
                     calendar: Calendar = .current, timeout: Duration = .seconds(45)) async -> [ScannedEvent]? {
        guard assistant.isConfigured else { return nil }
        let reply = await assistant.answerText(to: .textTask(prompt(for: text, now: now, calendar: calendar)), timeout: timeout)
        return reply.flatMap { decode($0, calendar: calendar) }
    }

    static func prompt(for text: String, now: Date, calendar: Calendar = .current) -> String {
        // In English like the rest of the prompt, with the date in the form the reply uses.
        let words = now.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "en_US"),
                                                   calendar: calendar, timeZone: calendar.timeZone))
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let iso = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let today = "\(words) (\(iso))"
        return """
        Find the events in the text below. It was read from a photo of a flyer, an invitation or a letter, so it may have scanning errors. Today is \(today).
        Reply with JSON only, no markdown and no commentary, in exactly this shape:
        {"events": [{"title": string, "date": "YYYY-MM-DD", "startTime": "HH:MM" or null, "endTime": "HH:MM" or null, "endDate": "YYYY-MM-DD" or null, "location": string or null, "isDeadline": boolean}]}
        Use 24-hour times. A date without a year is the next one on or after today. Leave startTime null for an event that lasts all day. \
        Name each event by what happens, such as "Spring Bake Sale". Put the place in location, with the street when the text gives one. \
        Mark RSVP dates and forms or payments that are due as deadlines. Leave out dates that are not events, such as the day a letter was written. \
        Do not invent events, times or places.

        Text:
        \(text)
        """
    }

    /// The events in a reply, tolerating code fences and words around the
    /// JSON. Nil when the reply is not the asked shape. An empty list means
    /// the provider found no events.
    static func decode(_ reply: String, calendar: Calendar = .current) -> [ScannedEvent]? {
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let json = try? JSONValue.parse(String(reply[open...close])),
              let items = json["events"]?.arrayValue else { return nil }
        return items.compactMap { event(from: $0, calendar: calendar) }
    }

    private static func event(from item: JSONValue, calendar: Calendar) -> ScannedEvent? {
        guard let title = item["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let day = item["date"]?.stringValue.flatMap({ date($0, calendar: calendar) }) else { return nil }
        let isDeadline = item["isDeadline"]?.boolValue ?? false
        let location = item["location"]?.stringValue ?? ""
        let lastDay = item["endDate"]?.stringValue.flatMap { date($0, calendar: calendar) } ?? day
        guard let startTime = item["startTime"]?.stringValue.flatMap(time) else {
            return ScannedEvent(title: title, start: day, end: max(lastDay, day), isAllDay: true, location: isDeadline ? "" : location,
                                isSelected: !isDeadline, source: "")
        }
        let start = calendar.date(bySettingHour: startTime.hour, minute: startTime.minute, second: 0, of: day) ?? day
        var end = item["endTime"]?.stringValue.flatMap(time).flatMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: lastDay)
        } ?? start.addingTimeInterval(FlyerEventExtractor.defaultLength)
        if end <= start { end = start.addingTimeInterval(FlyerEventExtractor.defaultLength) }
        return ScannedEvent(title: title, start: start, end: end, isAllDay: false, location: isDeadline ? "" : location,
                            isSelected: !isDeadline, source: "")
    }

    /// Midnight on "2026-11-12".
    private static func date(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "18:30".
    private static func time(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0.prefix(2)) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}
