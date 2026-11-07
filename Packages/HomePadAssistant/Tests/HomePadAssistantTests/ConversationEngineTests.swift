import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

/// A provider that replays scripted turns and records requests. No network.
final class ScriptedProvider: ChatProvider, @unchecked Sendable {
    let config: ProviderConfig
    private var turns: [[ChatStreamEvent]]
    private let failure: Error?
    private(set) var requests: [ChatRequest] = []

    init(_ descriptor: ProviderDescriptor, turns: [[ChatStreamEvent]], failure: Error? = nil) {
        self.config = ProviderConfig(descriptor: descriptor, apiKey: "test")
        self.turns = turns
        self.failure = failure
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        requests.append(request)
        let events = turns.isEmpty ? [] : turns.removeFirst()
        let failure = self.failure
        return AsyncThrowingStream { continuation in
            if let failure { return continuation.finish(throwing: failure) }
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func listModels() async throws -> [String] { [] }
}

@MainActor
@Suite struct ConversationEngineTests {
    let household = Household(store: SettingsStore(defaults: UserDefaults(suiteName: "assistant.tests.engine")!))

    func engine(tools: [AssistantTool], providers: [String: ScriptedProvider], events: Box<[AssistantEvent]>) -> ConversationEngine {
        let invoker = ToolInvoker(tools: tools, household: household, confirmations: ConfirmationCenter(), selfConfirmingTools: [])
        return ConversationEngine(invoker: invoker, emit: { events.value.append($0) }, onActivity: { _ in }) { config in
            providers[config.descriptor.id]!
        }
    }

    func input(_ text: String, tools: [AssistantTool], candidates: [ProviderDescriptor]) -> ConversationEngine.Input {
        ConversationEngine.Input(
            message: .user(text), history: [], tools: tools,
            candidates: candidates.map { ProviderConfig(descriptor: $0, apiKey: "k") }, system: { _ in "system" }
        )
    }

    @Test func runsToolLoopAndReturnsFinalText() async throws {
        var ran: [JSONValue] = []
        let tool = AssistantTool(name: "get_time", description: "Time") { args in
            ran.append(args)
            return "It is noon."
        }
        let provider = ScriptedProvider(ProviderCatalog.anthropic, turns: [
            [.textDelta("Checking."), .completed(.assistant("Checking.", toolCalls: [ToolCall(id: "t1", name: "get_time", arguments: #"{"city":"Rome"}"#)]), .toolUse)],
            [.textDelta("It is noon."), .completed(.assistant("It is noon."), .endTurn)],
        ])
        let events = Box<[AssistantEvent]>([])
        let output = try await engine(tools: [tool], providers: ["anthropic": provider], events: events)
            .run(input("Time in Rome?", tools: [tool], candidates: [ProviderCatalog.anthropic])) { _ in }
        #expect(output.text == "Checking. It is noon.")
        #expect(ran == [["city": "Rome"]])
        #expect(provider.requests.count == 2)
        let second = try #require(provider.requests.last)
        #expect(second.messages.last?.toolResults == [ToolResult(callID: "t1", name: "get_time", content: "It is noon.")])
        #expect(second.tools.map(\.name) == ["get_time"])
    }

    @Test func failsOverWhenFirstProviderErrorsBeforeOutput() async throws {
        let broken = ScriptedProvider(ProviderCatalog.openAI, turns: [], failure: AssistantError.http(status: 503, message: ""))
        let working = ScriptedProvider(ProviderCatalog.gemini, turns: [[.textDelta("Hi"), .completed(.assistant("Hi"), .endTurn)]])
        var used: [String] = []
        let output = try await engine(tools: [], providers: ["openai": broken, "gemini": working], events: Box([]))
            .run(input("Hello", tools: [], candidates: [ProviderCatalog.openAI, ProviderCatalog.gemini])) { used.append($0.id) }
        #expect(output.provider.id == "gemini")
        #expect(used == ["openai", "gemini"])
    }

    @Test func rejectsInvalidToolJSONWithoutRunningTheTool() async throws {
        var ran = false
        let tool = AssistantTool(name: "start_timer", description: "Timer", parameters: Schema.object(["seconds": Schema.number("s")], required: ["seconds"])) { _ in
            ran = true
            return "ok"
        }
        let provider = ScriptedProvider(ProviderCatalog.anthropic, turns: [
            [.completed(.assistant("", toolCalls: [ToolCall(id: "a", name: "start_timer", arguments: #"{"seconds": 6"#)]), .toolUse)],
            [.completed(.assistant("", toolCalls: [ToolCall(id: "b", name: "start_timer", arguments: "{}")]), .toolUse)],
            [.textDelta("Sorry."), .completed(.assistant("Sorry."), .endTurn)],
        ])
        _ = try await engine(tools: [tool], providers: ["anthropic": provider], events: Box([]))
            .run(input("Timer", tools: [tool], candidates: [ProviderCatalog.anthropic])) { _ in }
        #expect(!ran)
        let results = provider.requests.compactMap { $0.messages.last?.toolResults.first }
        #expect(results[0].isError && results[0].content.contains("INVALID_JSON"))
        #expect(results[1].isError && results[1].content == "Missing required argument: seconds.")
    }

    @Test func dropsImagesForTextOnlyModels() async throws {
        let provider = ScriptedProvider(ProviderCatalog.deepSeek, turns: [[.completed(.assistant("I can't see it."), .endTurn)]])
        var request = input("What is this?", tools: [], candidates: [ProviderCatalog.deepSeek])
        request.message.images = [ChatImage(data: Data([0xFF, 0xD8]))]
        _ = try await engine(tools: [], providers: ["deepseek": provider], events: Box([])).run(request) { _ in }
        let sent = try #require(provider.requests.first?.messages.last)
        #expect(sent.images.isEmpty)
        #expect(sent.text.contains("cannot see images"))
    }

    @Test func providerOrderRespectsRequestPersonDefaultAndFallback() {
        let order = ProviderRouter.order(requested: nil, personal: "gemini", householdDefault: "anthropic", fallback: ["openai", "gemini"], all: ["apple", "openai", "anthropic", "gemini"])
        #expect(order == ["gemini", "anthropic", "openai", "apple"])
        #expect(ProviderRouter.order(requested: "openai", personal: nil, householdDefault: "", fallback: [], all: ["apple", "openai"]) == ["openai", "apple"])
        // Nothing chosen: a provider with a saved key answers before Apple's on-device model.
        let keyed = ProviderRouter.unchosenOrder([ProviderCatalog.apple, ProviderCatalog.openAI, ProviderCatalog.anthropic]) { $0.id == "anthropic" }
        #expect(keyed == ["anthropic", "apple", "openai"])
    }

    @Test func toolSelectorKeepsCoreAndRelevantTools() {
        let names = ["control_device", "get_time", "get_weather", "start_timer", "play_music", "get_recipe", "scan_document", "add_event", "intercom_announce", "list_timers"]
        let tools = names.map { AssistantTool(name: $0, description: $0.replacingOccurrences(of: "_", with: " ")) { _ in "" } }
        let picked = ToolSelector.select(tools, for: "start a timer for the pasta", limit: 5).map(\.name)
        #expect(picked.prefix(3) == ["control_device", "get_time", "get_weather"])
        #expect(picked.contains("start_timer"))
        #expect(picked.count == 5)
    }
}

/// A reference box so closures in tests can collect values.
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
