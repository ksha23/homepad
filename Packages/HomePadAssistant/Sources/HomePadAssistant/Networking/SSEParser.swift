import Foundation

/// One Server-Sent Event.
public struct SSEEvent: Equatable, Sendable {
    /// The `event:` field, nil when the stream only sends `data:` lines (OpenAI, Gemini).
    public var name: String?
    public var data: String

    public init(name: String? = nil, data: String) {
        self.name = name
        self.data = data
    }
}

/// Incremental Server-Sent Events parser (WHATWG rules: `event:`, `data:`,
/// comments, blank-line dispatch, multi-line data joined with newlines).
public struct SSEParser: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []

    public init() {}

    /// Feeds one line without its line terminator. Returns an event when a blank line completes one.
    public mutating func feed(line rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": eventName = String(value)
        case "data": dataLines.append(String(value))
        default: break  // id, retry and unknown fields are not needed here
        }
        return nil
    }

    /// Flushes a final event when the stream ends without a trailing blank line.
    public mutating func finish() -> SSEEvent? {
        dispatch()
    }

    /// Parses a complete SSE body. Handy for tests and non-streaming fallbacks.
    public static func parse(_ text: String) -> [SSEEvent] {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in LineSplitter.lines(in: text) {
            if let event = parser.feed(line: line) { events.append(event) }
        }
        if let event = parser.finish() { events.append(event) }
        return events
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            eventName = nil
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(name: eventName, data: dataLines.joined(separator: "\n"))
    }
}

/// Splits a byte stream into lines, keeping empty lines (SSE needs them,
/// and `URLSession.AsyncBytes.lines` drops them).
struct LineSplitter: Sendable {
    private var buffer: [UInt8] = []

    /// Appends one byte. Returns a completed line at each `\n`.
    mutating func append(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else {
            buffer.append(byte)
            return nil
        }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }

    /// Splits a whole string the same way the network path does (byte-wise on `\n`,
    /// so `\r\n` keeps its `\r` for the parser to strip).
    static func lines(in text: String) -> [String] {
        var splitter = LineSplitter()
        var lines = text.utf8.compactMap { splitter.append($0) }
        if let tail = splitter.finish() { lines.append(tail) }
        return lines
    }

    /// Returns any trailing partial line at the end of the stream.
    mutating func finish() -> String? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll() }
        return String(decoding: buffer, as: UTF8.self)
    }
}
