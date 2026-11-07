import Foundation
import HAKit
import HomePadCore

/// Decoders for the responses HomePad reads.
enum HAResponses {
    /// Entity states from `/api/states`. Entries HAKit cannot decode are skipped.
    static func states(_ data: HAData) throws -> [HAState] {
        try [HAEntity](data: data).map(HAState.init(entity:))
    }

    /// The playlist URL from a `camera/stream` result, made absolute.
    static func streamURL(_ result: JSONValue, baseURL: URL) -> URL? {
        guard let path = result["url"]?.stringValue else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Numeric samples from a history response (an array with one array per entity).
    static func history(_ result: JSONValue) -> [SensorSample] {
        let rows = result.arrayValue?.first?.arrayValue ?? []
        return rows.compactMap { row in
            guard let value = row["state"]?.doubleValue,
                  let stamp = row["last_changed"]?.stringValue ?? row["last_updated"]?.stringValue,
                  let date = parseDate(stamp) else { return nil }
            return SensorSample(date: date, value: value)
        }
    }

    /// Home Assistant timestamps, with or without fractional seconds.
    static func parseDate(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}
