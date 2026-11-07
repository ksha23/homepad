import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

@Suite struct OpenAIResponsesTests {
    static let stream = """
    event: response.created
    data: {"type":"response.created","response":{"id":"resp_1","status":"in_progress","output":[]}}

    event: response.output_item.added
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_1","type":"reasoning","summary":[]}}

    event: response.output_item.done
    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_1","type":"reasoning","summary":[],"encrypted_content":"enc"}}

    event: response.output_item.added
    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_1","type":"message","role":"assistant","content":[]}}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":1,"content_index":0,"delta":"Checking"}

    event: response.output_item.added
    data: {"type":"response.output_item.added","output_index":2,"item":{"id":"fc_1","type":"function_call","call_id":"call_1","name":"get_weather","arguments":""}}

    event: response.function_call_arguments.delta
    data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":2,"delta":"{}"}

    event: response.output_item.done
    data: {"type":"response.output_item.done","output_index":2,"item":{"id":"fc_1","type":"function_call","call_id":"call_1","name":"get_weather","arguments":"{}"}}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[{"id":"rs_1","type":"reasoning","summary":[],"encrypted_content":"enc"},{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"output_text","text":"Checking"}]},{"id":"fc_1","type":"function_call","call_id":"call_1","name":"get_weather","arguments":"{}"},{"id":"rs_2","type":"reasoning","summary":[]}]}}

    """

    @Test func decodesTextFunctionCallsAndEchoItems() throws {
        let result = try OpenAIResponsesStreamDecoder.decodeAll(Self.stream)
        #expect(result.events.textDeltas == ["Checking"])
        #expect(result.events.startedTools == ["get_weather"])
        #expect(result.stop == .toolUse)
        #expect(result.message.toolCalls == [ToolCall(id: "call_1", name: "get_weather", arguments: "{}")])
        // The reasoning item without encrypted content cannot be replayed, so it is dropped.
        let echoTypes = result.message.providerState?.arrayValue?.compactMap { $0["type"]?.stringValue }
        #expect(echoTypes == ["reasoning", "message", "function_call"])
    }

    @Test func reportsIncompleteAndFailedResponses() throws {
        let incomplete = """
        data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}}

        """
        #expect(try OpenAIResponsesStreamDecoder.decodeAll(incomplete).stop == .maxTokens)
        let failed = #"data: {"type":"response.failed","response":{"status":"failed","error":{"message":"Bad model"}}}"# + "\n\n"
        #expect(throws: AssistantError.streamError("Bad model")) { try OpenAIResponsesStreamDecoder.decodeAll(failed) }
    }

    @Test func encodesStatelessRequestWithImagesToolsAndOutputs() throws {
        let image = ChatImage(data: Data([0xFF, 0xD8]))
        let request = ChatRequest(
            model: "gpt-6.1-sol", system: "Be brief.",
            messages: [
                .user("Look", images: [image]),
                .assistant("", toolCalls: [ToolCall(id: "call_1", name: "get_time", arguments: "{}")]),
                .toolResults([ToolResult(callID: "call_1", name: "get_time", content: "noon")]),
            ],
            tools: [Fixtures.timeTool]
        )
        let body = OpenAIResponsesEncoder(quirks: [.encryptedReasoning]).body(for: request)
        #expect(body["store"] == false)
        #expect(body["instructions"] == "Be brief.")
        #expect(body["include"] == ["reasoning.encrypted_content"])
        #expect(body["tools"]?.arrayValue?.first?["strict"] == false)
        let input = try #require(body["input"]?.arrayValue)
        #expect(input[0]["content"]?.arrayValue?[1]["type"] == "input_image")
        #expect(input[1] == ["type": "function_call", "call_id": "call_1", "name": "get_time", "arguments": "{}"])
        #expect(input[2] == ["type": "function_call_output", "call_id": "call_1", "output": "noon"])
    }

    @Test func replaysPreviousOutputItemsVerbatim() throws {
        let result = try OpenAIResponsesStreamDecoder.decodeAll(Self.stream)
        let body = OpenAIResponsesEncoder(quirks: []).body(for: ChatRequest(model: "grok-4.7", system: "", messages: [.user("Hi"), result.message]))
        #expect(body["include"] == nil)
        #expect(Array(body["input"]?.arrayValue?.dropFirst() ?? []) == result.message.providerState?.arrayValue)
    }

    @Test func providerPostsToResponsesWithBearerKey() async throws {
        let transport = MockTransport(body: Self.stream)
        let provider = OpenAIResponsesProvider(config: ProviderConfig(descriptor: ProviderCatalog.xAI, apiKey: "xai-key"), transport: transport)
        for try await _ in provider.stream(ChatRequest(model: "grok-4.7", system: "", messages: [.user("Hi")])) {}
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.x.ai/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-key")
    }
}
