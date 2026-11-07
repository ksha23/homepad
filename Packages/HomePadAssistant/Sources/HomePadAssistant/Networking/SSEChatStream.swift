import Foundation

/// Turns one wire format's SSE events into provider-neutral stream events.
/// Each provider has one. They are pure values, so tests feed them canned SSE text.
protocol ChatStreamDecoder {
    init()
    /// Decodes one SSE event. Throws when the provider reports an error mid-stream.
    mutating func decode(_ event: SSEEvent) throws -> [ChatStreamEvent]
    /// Builds the final assistant message once the stream ends.
    mutating func finish() throws -> (ChatMessage, StopReason)
}

extension ChatStreamDecoder {
    /// Decodes a whole SSE body at once. Used by tests.
    static func decodeAll(_ body: String) throws -> (events: [ChatStreamEvent], message: ChatMessage, stop: StopReason) {
        var decoder = Self()
        var events: [ChatStreamEvent] = []
        for event in SSEParser.parse(body) {
            events += try decoder.decode(event)
        }
        let (message, stop) = try decoder.finish()
        return (events, message, stop)
    }
}

/// Runs an HTTP request and pipes its SSE body through a decoder.
enum SSEChatStream {
    static func run<Decoder: ChatStreamDecoder>(
        _ request: URLRequest, transport: HTTPTransport, decoder: Decoder.Type
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var decoder = Decoder()
                    var parser = SSEParser()
                    let lines = try await transport.lines(for: request)
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard let event = parser.feed(line: line) else { continue }
                        for output in try decoder.decode(event) { continuation.yield(output) }
                    }
                    if let event = parser.finish() {
                        for output in try decoder.decode(event) { continuation.yield(output) }
                    }
                    let (message, stop) = try decoder.finish()
                    continuation.yield(.completed(message, stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
