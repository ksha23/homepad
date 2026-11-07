import Foundation
import HomePadCore

/// Runs one request end to end: picks a provider, streams the answer, runs
/// tool calls for up to `maxRounds` rounds, and fails over to the next
/// provider when one fails before anything happened.
@MainActor
final class ConversationEngine {
    static let maxRounds = 6
    /// The on-device model has a small context, so it gets the most relevant tools only.
    static let onDeviceToolLimit = 8

    struct Input {
        var message: ChatMessage
        var history: [ChatMessage]
        var tools: [AssistantTool]
        var candidates: [ProviderConfig]
        /// System prompt for a provider (the on-device model gets a compact one).
        var system: (ProviderDescriptor) -> String
    }

    struct Output {
        var text: String
        var provider: ProviderDescriptor
        var citations: [URL]
        /// What each tool call returned, kept with the turn for later context.
        var actions: [String] = []
    }

    private let invoker: ToolInvoker
    private let emit: (AssistantEvent) -> Void
    private let onActivity: (String) -> Void
    private let makeProvider: (ProviderConfig) -> any ChatProvider
    /// Once text streamed or a tool ran, switching providers would repeat side effects.
    private var hasOutput = false
    private var actions: [String] = []

    init(
        invoker: ToolInvoker, emit: @escaping (AssistantEvent) -> Void, onActivity: @escaping (String) -> Void,
        makeProvider: @escaping (ProviderConfig) -> any ChatProvider = { ProviderFactory.make($0) }
    ) {
        self.invoker = invoker
        self.emit = emit
        self.onActivity = onActivity
        self.makeProvider = makeProvider
    }

    func run(_ input: Input, onProvider: (ProviderDescriptor) -> Void) async throws -> Output {
        guard !input.candidates.isEmpty else { throw AssistantError.noProvider }
        let hasImages = !input.message.images.isEmpty
        // With a photo attached, providers that can see it go first.
        let ordered = input.candidates.enumerated().sorted { lhs, rhs in
            let left = !hasImages || Self.canSeeImages(lhs.element.descriptor)
            let right = !hasImages || Self.canSeeImages(rhs.element.descriptor)
            return left != right ? left : lhs.offset < rhs.offset
        }.map(\.element)

        var lastError: Error = AssistantError.noProvider
        for (index, config) in ordered.enumerated() {
            onProvider(config.descriptor)
            do {
                return try await loop(input, provider: makeProvider(config))
            } catch {
                lastError = error
                let canRetry = !hasOutput && index < ordered.count - 1 && !(error is CancellationError)
                    && ((error as? AssistantError)?.allowsFailover ?? true)
                guard canRetry else { throw error }
                Log.make("Assistant").notice("Provider \(config.descriptor.id, privacy: .public) failed, trying the next one")
            }
        }
        throw lastError
    }

    private func loop(_ input: Input, provider: any ChatProvider) async throws -> Output {
        let descriptor = provider.descriptor
        var messages = input.history + [prepared(input.message, for: descriptor)]
        let tools = offeredTools(input.tools, for: descriptor, request: input.message.text)
        let specs = tools.map { ToolSpec($0) }
        let executor: ToolExecutor? = descriptor.wireFormat == .appleOnDevice ? makeExecutor() : nil
        var text = ""
        var citations: [URL] = []

        for _ in 0..<Self.maxRounds {
            try Task.checkCancellation()
            let request = ChatRequest(model: provider.config.model, system: input.system(descriptor), messages: messages, tools: specs, executor: executor)
            var completed: (ChatMessage, StopReason)?
            var separatorPending = !text.isEmpty
            for try await event in provider.stream(request) {
                switch event {
                case .textDelta(let delta):
                    let chunk = separatorPending && !(text.last?.isWhitespace ?? true) ? " " + delta : delta
                    separatorPending = false
                    text += chunk
                    hasOutput = true
                    emit(.textDelta(chunk))
                case .toolCallStarted(let name):
                    onActivity(name)
                case .completed(let message, let stop):
                    completed = (message, stop)
                }
            }
            guard let (message, stop) = completed else { throw AssistantError.badResponse("The answer ended early.") }
            citations += message.citations
            messages.append(message)

            if stop == .refusal, text.isEmpty {
                throw AssistantError.refused
            }
            guard !message.toolCalls.isEmpty, stop != .refusal, stop != .maxTokens else {
                return Output(text: text, provider: descriptor, citations: citations, actions: actions)
            }
            var results: [ToolResult] = []
            for call in message.toolCalls {
                results.append(await execute(call))
            }
            messages.append(.toolResults(results))
        }
        let note = text.isEmpty ? "That took too many steps, so I stopped." : " I had to stop before finishing."
        text += note
        emit(.textDelta(note))
        return Output(text: text, provider: descriptor, citations: citations, actions: actions)
    }

    /// For providers that run their own tool loop (Apple's on-device model).
    private func makeExecutor() -> ToolExecutor {
        { @MainActor [weak self] (call: ToolCall) async -> ToolResult in
            guard let self else { return ToolResult(callID: call.id, name: call.name, content: "Canceled.", isError: true) }
            return await self.execute(call)
        }
    }

    private func execute(_ call: ToolCall) async -> ToolResult {
        hasOutput = true
        onActivity(call.name)
        emit(.toolCall(name: call.name, arguments: call.arguments))
        let result = await invoker.invoke(call)
        actions.append("\(call.name)\(result.isError ? " failed" : ""): \(result.content.prefix(200))")
        emit(.toolResult(name: call.name, result: result.content))
        return result
    }

    private func offeredTools(_ tools: [AssistantTool], for descriptor: ProviderDescriptor, request: String) -> [AssistantTool] {
        guard descriptor.supportsTools else { return [] }
        guard descriptor.wireFormat == .appleOnDevice else { return tools }
        return ToolSelector.select(tools, for: request, limit: Self.onDeviceToolLimit)
    }

    /// Drops images a model cannot see and says so, rather than failing the request.
    private func prepared(_ message: ChatMessage, for descriptor: ProviderDescriptor) -> ChatMessage {
        guard !message.images.isEmpty, !Self.canSeeImages(descriptor) else { return message }
        var copy = message
        copy.images = []
        copy.text += "\n\n(A photo was attached, but this model cannot see images. Say so briefly.)"
        return copy
    }

    static func canSeeImages(_ descriptor: ProviderDescriptor) -> Bool {
        descriptor.wireFormat == .appleOnDevice ? AppleFoundationProvider.supportsImages : descriptor.supportsImages
    }
}
