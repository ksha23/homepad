import Foundation

/// The parts of an HTTP/1.x request the camera server cares about.
struct HTTPRequest: Equatable, Sendable {
    var method: String
    /// Percent-decoded path without the query, for example "/stream.mjpeg".
    var path: String
    /// Query parameters. When a name repeats, the first value wins.
    var query: [String: String]
    /// Header fields with lowercased names.
    var headers: [String: String]
    var version: String
}

/// Parses the request line and headers of an HTTP/1.x request. Bodies are
/// ignored because the camera server only answers GET and HEAD.
enum HTTPRequestParser {
    enum Outcome: Equatable {
        /// More bytes are needed before the header block ends.
        case incomplete
        case invalid(String)
        case complete(HTTPRequest)
    }

    /// Requests whose header block is larger than this are rejected.
    static let maximumHeaderBytes = 8 * 1024
    private static let terminator = Data("\r\n\r\n".utf8)

    static func parse(_ data: Data) -> Outcome {
        guard let end = data.range(of: terminator) else {
            return data.count > maximumHeaderBytes ? .invalid("Header block too large") : .incomplete
        }
        let headerBytes = data[data.startIndex..<end.lowerBound]
        guard headerBytes.count <= maximumHeaderBytes else { return .invalid("Header block too large") }
        guard let text = String(data: headerBytes, encoding: .utf8) else { return .invalid("Header is not UTF-8") }

        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return .invalid("Malformed request line") }
        let method = String(parts[0])
        let target = String(parts[1])
        let version = String(parts[2])
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return .invalid("Malformed method") }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else { return .invalid("Unsupported HTTP version") }
        guard target.hasPrefix("/") else { return .invalid("Unsupported request target") }

        let pathAndQuery = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(pathAndQuery[0])
        let path = rawPath.removingPercentEncoding ?? rawPath
        let query = pathAndQuery.count > 1 ? parseQuery(String(pathAndQuery[1])) : [:]

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid("Malformed header line") }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, !name.contains(" ") else { return .invalid("Malformed header name") }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        return .complete(HTTPRequest(method: method, path: path, query: query, headers: headers, version: version))
    }

    /// Splits `a=1&b=two%20words` into a dictionary. `+` means space, as in forms.
    static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = decode(pieces[0])
            guard !name.isEmpty, result[name] == nil else { continue }
            result[name] = pieces.count > 1 ? decode(pieces[1]) : ""
        }
        return result
    }

    private static func decode(_ component: Substring) -> String {
        let spaced = component.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
