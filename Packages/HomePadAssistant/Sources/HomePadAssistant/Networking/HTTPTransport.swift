import Foundation
import HomePadCore

/// The network seam. Providers only talk to this, so tests can swap in canned responses.
public protocol HTTPTransport: Sendable {
    /// Sends a request and streams the response body line by line (empty lines included).
    func lines(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error>
    /// Sends a request and returns the whole body. Throws `AssistantError.http` for non-2xx.
    func data(for request: URLRequest) async throws -> Data
}

/// `URLSession` implementation used in the app.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lines(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 16_384 { break }
            }
            throw AssistantError.http(status: status, message: APIErrorMessage.extract(from: body))
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                var splitter = LineSplitter()
                do {
                    for try await byte in bytes {
                        if let line = splitter.append(byte) { continuation.yield(line) }
                    }
                    if let line = splitter.finish() { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AssistantError.http(status: status, message: APIErrorMessage.extract(from: data))
        }
        return data
    }
}

/// Pulls a human-readable message out of the many error body shapes vendors use.
enum APIErrorMessage {
    static func extract(from data: Data) -> String {
        guard let json = try? JSONValue(data: data) else {
            return String(decoding: data.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return extract(from: json) ?? ""
    }

    /// Handles `{"error":{"message"}}`, `[{"error":{...}}]` (Gemini), `{"error":"..."}` and `{"message":"..."}`.
    static func extract(from json: JSONValue) -> String? {
        if let first = json.arrayValue?.first { return extract(from: first) }
        if let message = json["error"]?["message"]?.stringValue { return message }
        if let message = json["error"]?.stringValue { return message }
        if let message = json["message"]?.stringValue { return message }
        if let detail = json["detail"]?.stringValue { return detail }
        return nil
    }
}

extension URLRequest {
    /// A JSON POST with the given headers.
    static func jsonPost(_ url: URL, body: JSONValue, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = Data(body.jsonString().utf8)
        return request
    }

    /// A GET with the given headers.
    static func get(_ url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }
}
