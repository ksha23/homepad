import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

@Suite struct AnthropicTests {
    static let toolStream = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig=="}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

    event: ping
    data: {"type":"ping"}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Turning them off."}}

    event: content_block_start
    data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"control_device","input":{}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"actions\\": [{\\"device\\""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":": \\"lights\\", \\"action\\": \\"turn_off\\"}]}"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":40}}

    event: message_stop
    data: {"type":"message_stop"}

    """

    @Test func decodesTextAndAccumulatesToolInput() throws {
        let result = try AnthropicStreamDecoder.decodeAll(Self.toolStream)
        #expect(result.stop == .toolUse)
        #expect(result.message.text == "Turning them off.")
        #expect(result.events.textDeltas == ["Turning them off."])
        #expect(result.events.startedTools == ["control_device"])
        let call = try #require(result.message.toolCalls.first)
        #expect(call.id == "toolu_1")
        #expect(try JSONValue.parse(call.arguments) == ["actions": [["device": "lights", "action": "turn_off"]]])
    }

    @Test func echoesThinkingBlocksUnchanged() throws {
        let result = try AnthropicStreamDecoder.decodeAll(Self.toolStream)
        let echo = try #require(result.message.providerState?.arrayValue)
        #expect(echo.count == 3)
        #expect(echo[0] == ["type": "thinking", "thinking": "", "signature": "sig=="])
        #expect(echo[2]["input"] == ["actions": [["device": "lights", "action": "turn_off"]]])

        let body = AnthropicEncoder().body(for: ChatRequest(model: "claude-opus-5-5", system: "", messages: [.user("Lights off"), result.message]))
        #expect(body["messages"]?.arrayValue?[1]["content"]?.arrayValue == echo)
    }

    @Test func dropsDeclinedAttemptBeforeFallbackBlock() throws {
        let body = """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":"a"}}

        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":"Partial "}}

        data: {"type":"content_block_start","index":2,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-5"}}}

        data: {"type":"content_block_start","index":3,"content_block":{"type":"text","text":"rest"}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        """
        let result = try AnthropicStreamDecoder.decodeAll(body)
        #expect(result.message.text == "Partial rest")
        let types = result.message.providerState?.arrayValue?.compactMap { $0["type"]?.stringValue }
        #expect(types == ["text", "text"])
    }

    @Test func mapsRefusalAndErrors() throws {
        let refusal = try AnthropicStreamDecoder.decodeAll(#"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"# + "\n\n")
        #expect(refusal.stop == .refusal)
        #expect(throws: AssistantError.streamError("Overloaded")) {
            try AnthropicStreamDecoder.decodeAll("event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n")
        }
    }

    @Test func encodesImagesToolsResultsEffortAndFallbacks() throws {
        let image = ChatImage(data: Data([0xFF, 0xD8, 0xFF]))
        let request = ChatRequest(
            model: "claude-opus-5-5", system: "You are HomePad.",
            messages: [
                .user("Earlier"), .assistant("Sure."),
                .user("What is this?", images: [image]),
                .assistant("", toolCalls: [ToolCall(id: "toolu_9", name: "get_time", arguments: #"{"city":"Rome"}"#)]),
                .toolResults([ToolResult(callID: "toolu_9", name: "get_time", content: "boom", isError: true)]),
            ],
            tools: [Fixtures.timeTool]
        )
        let encoder = AnthropicEncoder()
        let body = encoder.body(for: request)
        #expect(body["system"] == "You are HomePad.")
        #expect(body["max_tokens"] == 64000)
        #expect(body["output_config"] == ["effort": "low"])
        #expect(body["fallbacks"] == "default")
        #expect(body["tools"]?.arrayValue?.first == [
            "name": "get_time", "description": "Current time", "eager_input_streaming": true,
            "input_schema": Fixtures.timeTool.parameters,
        ])
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages.map { $0["role"]?.stringValue } == ["user", "assistant", "user", "assistant", "user"])
        let userBlocks = try #require(messages[2]["content"]?.arrayValue)
        #expect(userBlocks[0]["source"] == ["type": "base64", "media_type": "image/jpeg", "data": "/9j/"])
        #expect(userBlocks[1] == ["type": "text", "text": "What is this?"])
        #expect(messages[3]["content"]?.arrayValue?.first?["input"] == ["city": "Rome"])
        #expect(messages[4]["content"]?.arrayValue?.first == [
            "type": "tool_result", "tool_use_id": "toolu_9", "content": "boom", "is_error": true,
        ])
        #expect(encoder.headers(apiKey: "k", model: "claude-opus-5-5") == [
            "anthropic-version": "2023-06-01", "x-api-key": "k", "anthropic-beta": "server-side-fallback-2026-07-01",
        ])
    }

    @Test func leavesNewerOptionsOffForOlderModels() {
        let body = AnthropicEncoder().body(for: ChatRequest(model: "claude-3-5-haiku-latest", system: "", messages: [.user("Hi")]))
        #expect(body["output_config"] == nil)
        #expect(body["fallbacks"] == nil)
        #expect(body["max_tokens"] == 8192)
        #expect(AnthropicEncoder().headers(apiKey: nil, model: "claude-3-5-haiku-latest")["anthropic-beta"] == nil)
    }

    @Test func mergesConsecutiveUserTurns() {
        let messages = AnthropicEncoder().messages(for: [.user("One"), .user("Two")])
        #expect(messages.count == 1)
        #expect(messages[0]["content"]?.arrayValue?.count == 2)
    }

    @Test func providerSendsToMessagesEndpoint() async throws {
        let transport = MockTransport(body: Self.toolStream)
        let provider = AnthropicProvider(config: ProviderConfig(descriptor: ProviderCatalog.anthropic, apiKey: "test"), transport: transport)
        var completed: ChatMessage?
        for try await event in provider.stream(ChatRequest(model: "claude-opus-5-5", system: "", messages: [.user("Hi")])) {
            if case .completed(let message, _) = event { completed = message }
        }
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test")
        #expect(completed?.toolCalls.count == 1)
    }

    /// Claude defaults to Haiku 5.5 at low effort with adaptive thinking (no
    /// `thinking` field) and no server-side fallback, which Haiku does not take.
    @Test func haikuIsTheDefaultAtLowEffort() throws {
        #expect(ProviderCatalog.anthropic.defaultModel == "claude-haiku-5-5")
        let encoder = AnthropicEncoder()
        let body = encoder.body(for: ChatRequest(model: "claude-haiku-5-5", system: "", messages: [.user("Hi")]))
        guard case .object(let fields) = body else { Issue.record("not an object"); return }
        #expect(fields["output_config"] == ["effort": "low"])
        #expect(fields["thinking"] == nil)
        #expect(fields["fallbacks"] == nil)
        #expect(encoder.headers(apiKey: "k", model: "claude-haiku-5-5")["anthropic-beta"] == nil)
    }
}
