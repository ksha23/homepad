import Foundation
import HomePadCore

// Small pieces the wire format encoders and decoders share.

extension JSONValue {
    /// Decodes a JSON document from raw bytes, such as a response body.
    init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension ChatMessage {
    /// Provider items to send back unchanged inside a tool loop (Claude thinking
    /// blocks, Gemini thought signatures, OpenAI encrypted reasoning), or nil
    /// when the message is rebuilt from its text and tool calls.
    var echoedItems: [JSONValue]? {
        guard let items = providerState?.arrayValue, !items.isEmpty else { return nil }
        return items
    }

    /// Groups messages into alternating turns, for APIs that reject two turns
    /// in a row from the same role (Claude, Gemini). Neighbors that map to the
    /// same role are merged, and messages with no content are skipped.
    static func alternatingTurns(
        _ messages: [ChatMessage], role: (ChatMessage) -> String, content: (ChatMessage) -> [JSONValue]
    ) -> [(role: String, content: [JSONValue])] {
        var turns: [(role: String, content: [JSONValue])] = []
        for message in messages {
            let speaker = role(message)
            let items = content(message)
            guard !items.isEmpty else { continue }
            if let last = turns.last, last.role == speaker {
                turns[turns.count - 1].content += items
            } else {
                turns.append((speaker, items))
            }
        }
        return turns
    }
}

extension ToolCall {
    /// The arguments as a JSON object, or `{}` when the model sent invalid JSON.
    var argumentsObject: JSONValue {
        (try? JSONValue.parse(arguments)) ?? [:]
    }
}

extension AssistantError {
    /// An error a provider reported inside its stream, with the vendor's
    /// message when the payload carries one.
    static func reported(in payload: JSONValue, fallback: String) -> AssistantError {
        .streamError(APIErrorMessage.extract(from: payload) ?? fallback)
    }
}
