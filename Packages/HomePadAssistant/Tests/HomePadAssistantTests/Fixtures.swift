import Foundation
import HomePadCore
@testable import HomePadAssistant

/// Shared test data.
enum Fixtures {
    static let timeTool = ToolSpec(
        name: "get_time", description: "Current time",
        parameters: Schema.object(["city": Schema.string("City name")])
    )

    static let emptyTool = ToolSpec(name: "list_timers", description: "List timers", parameters: Schema.object([:]))
}

extension Array where Element == ChatStreamEvent {
    var textDeltas: [String] {
        compactMap { if case .textDelta(let text) = $0 { text } else { nil } }
    }

    var startedTools: [String] {
        compactMap { if case .toolCallStarted(let name) = $0 { name } else { nil } }
    }
}

/// A transport that records the request and replays a canned SSE body. Never touches the network.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let body: String
    private let lock = NSLock()
    private var captured: [URLRequest] = []

    init(body: String) {
        self.body = body
    }

    var requests: [URLRequest] { lock.withLock { captured } }

    func lines(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        lock.withLock { captured.append(request) }
        let lines = LineSplitter.lines(in: body)
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
    }

    func data(for request: URLRequest) async throws -> Data {
        lock.withLock { captured.append(request) }
        return Data(body.utf8)
    }
}

extension URLRequest {
    var jsonBody: JSONValue? {
        httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }
}
