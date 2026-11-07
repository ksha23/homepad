import Foundation
import HomePadCore

/// Typed, forgiving access to a tool's JSON arguments. Models sometimes send
/// numbers as strings or dates in several formats, so readers accept both.
struct ToolArguments {
    let json: JSONValue

    init(_ json: JSONValue) {
        self.json = json
    }

    func string(_ key: String) -> String? {
        guard let value = json[key] else { return nil }
        let text = value.stringValue ?? value.doubleValue.map { String($0) }
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func double(_ key: String) -> Double? {
        json[key]?.doubleValue
    }

    func date(_ key: String, timeZone: TimeZone = .current) -> Date? {
        string(key).flatMap { FlexibleDateParser.parse($0, timeZone: timeZone) }
    }

    /// The non-empty strings in an array, for example `items: ["eggs", "milk"]`.
    func strings(_ key: String) -> [String] {
        (json[key]?.arrayValue ?? []).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }

    func array(_ key: String) -> [ToolArguments] {
        (json[key]?.arrayValue ?? []).map(ToolArguments.init)
    }

    func requireString(_ key: String) throws -> String {
        guard let value = string(key) else { throw ToolError("Missing \(key).") }
        return value
    }
}

/// Parses ISO 8601 with or without seconds or a time zone, and plain dates.
/// Times without a zone are read in the home's zone.
enum FlexibleDateParser {
    static func parse(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
