import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

@Suite struct GeminiTests {
    static let stream = """
    data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Let me "}]}}]}\r
    \r
    data: {"candidates":[{"content":{"role":"model","parts":[{"text":"check."},{"functionCall":{"id":"fc1","name":"get_weather","args":{}},"thoughtSignature":"SIG1"},{"functionCall":{"id":"fc2","name":"get_time","args":{"city":"Oslo"}}}]},"finishReason":"STOP"}]}\r
    \r

    """

    @Test func decodesTextAndFunctionCalls() throws {
        let result = try GeminiStreamDecoder.decodeAll(Self.stream)
        #expect(result.message.text == "Let me check.")
        #expect(result.stop == .toolUse)
        #expect(result.message.toolCalls == [
            ToolCall(id: "fc1", name: "get_weather", arguments: "{}"),
            ToolCall(id: "fc2", name: "get_time", arguments: #"{"city":"Oslo"}"#),
        ])
        #expect(result.events.startedTools == ["get_weather", "get_time"])
    }

    @Test func keepsThoughtSignaturesAndOrderWhenEchoing() throws {
        let result = try GeminiStreamDecoder.decodeAll(Self.stream)
        let results = ChatMessage.toolResults([
            ToolResult(callID: "fc1", name: "get_weather", content: "Sunny"),
            ToolResult(callID: "fc2", name: "get_time", content: "9 AM"),
        ])
        let body = GeminiEncoder().body(for: ChatRequest(model: "gemini-3.8-flash", system: "Hi", messages: [.user("Weather?"), result.message, results]))
        let contents = try #require(body["contents"]?.arrayValue)
        #expect(contents.map { $0["role"]?.stringValue } == ["user", "model", "user"])
        let modelParts = try #require(contents[1]["parts"]?.arrayValue)
        #expect(modelParts[2]["thoughtSignature"] == "SIG1")
        let responses = try #require(contents[2]["parts"]?.arrayValue)
        #expect(responses.map { $0["functionResponse"]?["id"]?.stringValue } == ["fc1", "fc2"])
        #expect(responses[0]["functionResponse"]?["response"] == ["result": "Sunny"])
    }

    @Test func encodesSystemImagesToolsAndThinkingLevel() throws {
        let image = ChatImage(data: Data([0xFF, 0xD8]))
        let request = ChatRequest(
            model: "gemini-4-argon", system: "Be kind.", messages: [.user("What is it?", images: [image])],
            tools: [Fixtures.timeTool, Fixtures.emptyTool]
        )
        let body = GeminiEncoder().body(for: request)
        #expect(body["systemInstruction"] == ["parts": [["text": "Be kind."]]])
        #expect(body["generationConfig"] == ["thinkingConfig": ["thinkingLevel": "low"]])
        let parts = try #require(body["contents"]?.arrayValue?.first?["parts"]?.arrayValue)
        #expect(parts[1] == ["inlineData": ["mimeType": "image/jpeg", "data": "/9g="]])
        let declarations = try #require(body["tools"]?.arrayValue?.first?["functionDeclarations"]?.arrayValue)
        // Empty `required` lists are dropped, and tools without parameters omit the field.
        #expect(declarations[0]["parameters"]?["required"] == nil)
        #expect(declarations[0]["parameters"]?["properties"]?["city"]?["type"] == "string")
        #expect(declarations[1]["parameters"] == nil)
        #expect(GeminiEncoder.usesThinkingLevel("gemini-2.5-flash") == false)
    }

    @Test func omitsLocallyGeneratedCallIDs() throws {
        let body = #"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"get_time","args":{}}}]},"finishReason":"STOP"}]}"# + "\n\n"
        let result = try GeminiStreamDecoder.decodeAll(body)
        let call = try #require(result.message.toolCalls.first)
        let encoded = GeminiEncoder().body(for: ChatRequest(model: "gemini-2.5-flash", system: "", messages: [
            .user("Time?"), .assistant("", toolCalls: [call]),
            .toolResults([ToolResult(callID: call.id, name: "get_time", content: "noon")]),
        ]))
        let response = encoded["contents"]?.arrayValue?[2]["parts"]?.arrayValue?.first?["functionResponse"]
        #expect(response?["id"] == nil)
        #expect(response?["name"] == "get_time")
    }

    @Test func reportsBlockedPromptsAndErrors() throws {
        let blocked = #"data: {"promptFeedback":{"blockReason":"SAFETY"}}"# + "\n\n"
        #expect(try GeminiStreamDecoder.decodeAll(blocked).stop == .refusal)
        let error = #"data: {"error":{"code":400,"message":"Bad key"}}"# + "\n\n"
        #expect(throws: AssistantError.streamError("Bad key")) { try GeminiStreamDecoder.decodeAll(error) }
    }

    @Test func providerUsesSSEEndpointAndKeyHeader() async throws {
        let transport = MockTransport(body: Self.stream)
        let provider = GeminiProvider(config: ProviderConfig(descriptor: ProviderCatalog.gemini, apiKey: "g-key"), transport: transport)
        for try await _ in provider.stream(ChatRequest(model: "gemini-3.8-flash", system: "", messages: [.user("Hi")])) {}
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
    }

    @Test func parsesModelListKeepingChatModels() throws {
        let data = Data(#"{"models":[{"name":"models/gemini-3.8-flash","supportedGenerationMethods":["generateContent","countTokens"]},{"name":"models/text-embedding-005","supportedGenerationMethods":["embedContent"]}]}"#.utf8)
        #expect(GeminiProvider.modelIDs(in: try JSONValue(data: data)) == ["gemini-3.8-flash"])
    }
}
