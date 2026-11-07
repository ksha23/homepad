import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

@Suite struct OpenAIChatTests {
    // MARK: Streaming

    @Test func streamsTextDeltas() throws {
        let body = """
        data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"Hel"}}]}

        data: {"choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":"stop"}]}

        data: [DONE]

        """
        let result = try OpenAIChatStreamDecoder.decodeAll(body)
        #expect(result.message.text == "Hello")
        #expect(result.stop == .endTurn)
        #expect(result.events.textDeltas == ["Hel", "lo"])
    }

    @Test func accumulatesParallelToolCallsFromFragments() throws {
        let body = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"control_device","arguments":""}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"actions\\":"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_b","type":"function","function":{"name":"get_time","arguments":"{}"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"[]}"}}]}}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """
        let result = try OpenAIChatStreamDecoder.decodeAll(body)
        #expect(result.stop == .toolUse)
        #expect(result.message.toolCalls == [
            ToolCall(id: "call_a", name: "control_device", arguments: #"{"actions":[]}"#),
            ToolCall(id: "call_b", name: "get_time", arguments: "{}"),
        ])
        #expect(result.events.startedTools == ["control_device", "get_time"])
    }

    @Test func handlesWholeToolCallsWithoutIndex() throws {
        // Some compatible servers send each call complete, keyed only by id.
        let body = """
        data: {"choices":[{"delta":{"tool_calls":[{"id":"abc123def","function":{"name":"get_weather","arguments":"{}"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"id":"zyx987wvu","function":{"name":"get_time","arguments":{"city":"Paris"}}}]},"finish_reason":"tool_calls"}]}

        """
        let result = try OpenAIChatStreamDecoder.decodeAll(body)
        #expect(result.message.toolCalls.map(\.name) == ["get_weather", "get_time"])
        #expect(result.message.toolCalls[1].arguments == #"{"city":"Paris"}"#)
    }

    @Test func capturesReasoningAndCitations() throws {
        let body = """
        data: {"citations":["https://example.com/a"],"choices":[{"delta":{"reasoning_content":"think "}}]}

        data: {"search_results":[{"url":"https://example.com/b"}],"choices":[{"delta":{"content":"Answer"},"finish_reason":"stop"}]}

        """
        let result = try OpenAIChatStreamDecoder.decodeAll(body)
        #expect(result.message.providerState?["reasoning_content"]?.stringValue == "think ")
        #expect(result.message.citations.map(\.absoluteString) == ["https://example.com/a", "https://example.com/b"])
    }

    @Test func throwsOnMidStreamError() {
        let body = "data: {\"error\":{\"message\":\"overloaded\"}}\n\n"
        #expect(throws: AssistantError.streamError("overloaded")) {
            try OpenAIChatStreamDecoder.decodeAll(body)
        }
    }

    // MARK: Encoding

    @Test func encodesSystemImagesToolsAndToolResults() throws {
        let image = ChatImage(data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2]))
        let request = ChatRequest(
            model: "muse-spark-1.3", system: "Be brief.",
            messages: [
                .user("What is this?", images: [image]),
                .assistant("", toolCalls: [ToolCall(id: "c1", name: "get_time", arguments: "{}")]),
                .toolResults([ToolResult(callID: "c1", name: "get_time", content: "3 PM")]),
            ],
            tools: [Fixtures.timeTool]
        )
        let body = OpenAIChatEncoder(descriptor: ProviderCatalog.meta).body(for: request)
        #expect(body["stream"] == true)
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages[0] == ["role": "system", "content": "Be brief."])
        let parts = try #require(messages[1]["content"]?.arrayValue)
        #expect(parts[0] == ["type": "text", "text": "What is this?"])
        #expect(parts[1]["image_url"]?["url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true)
        #expect(messages[2]["content"] == .null)
        #expect(messages[2]["tool_calls"]?.arrayValue?.first?["function"]?["name"] == "get_time")
        #expect(messages[3] == ["role": "tool", "tool_call_id": "c1", "content": "3 PM"])
        #expect(body["tools"]?.arrayValue?.first?["function"]?["name"] == "get_time")
    }

    @Test func omitsToolsForProvidersWithoutToolSupport() {
        let request = ChatRequest(model: "sonar-pro", system: "", messages: [.user("Hi")], tools: [Fixtures.timeTool])
        let body = OpenAIChatEncoder(descriptor: ProviderCatalog.perplexity).body(for: request)
        #expect(body["tools"] == nil)
        #expect(body["messages"]?.arrayValue?.first == ["role": "user", "content": "Hi"])
    }

    @Test func echoesReasoningContentForDeepSeek() {
        var assistant = ChatMessage.assistant("", toolCalls: [ToolCall(id: "c1", name: "get_time", arguments: "{}")])
        assistant.providerState = ["reasoning_content": "because"]
        let request = ChatRequest(model: "deepseek-v4-pro", system: "", messages: [.user("Hi"), assistant])
        let deepSeek = OpenAIChatEncoder(descriptor: ProviderCatalog.deepSeek).body(for: request)
        let mistral = OpenAIChatEncoder(descriptor: ProviderCatalog.mistral).body(for: request)
        #expect(deepSeek["messages"]?.arrayValue?[1]["reasoning_content"] == "because")
        #expect(mistral["messages"]?.arrayValue?[1]["reasoning_content"] == nil)
    }

    @Test func filtersNonChatModelsFromList() throws {
        let data = Data(#"{"object":"list","data":[{"id":"whisper-large-v3"},{"id":"openai/gpt-oss-120b"},{"id":"llama-guard-4"}]}"#.utf8)
        #expect(OpenAICompatibleProvider.modelIDs(in: try JSONValue(data: data)) == ["openai/gpt-oss-120b"])
    }
}
