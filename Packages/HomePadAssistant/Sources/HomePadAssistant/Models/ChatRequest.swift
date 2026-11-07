import Foundation
import HomePadCore

/// A tool as providers see it: name, description and JSON Schema parameters.
public struct ToolSpec: Hashable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public init(_ tool: AssistantTool) {
        self.init(name: tool.name, description: tool.description, parameters: tool.parameters)
    }

    /// True when the schema declares at least one property.
    public var hasParameters: Bool {
        !(parameters["properties"]?.objectValue ?? [:]).isEmpty
    }
}

/// Runs one tool call. Providers that drive their own tool loop (Apple's
/// on-device model) call this. HTTP providers return tool calls instead.
public typealias ToolExecutor = @MainActor @Sendable (ToolCall) async -> ToolResult

/// One model call: the conversation so far plus the tools on offer.
public struct ChatRequest: Sendable {
    public var model: String
    public var system: String
    public var messages: [ChatMessage]
    public var tools: [ToolSpec]
    /// Set for providers that execute tools themselves.
    public var executor: ToolExecutor?

    public init(model: String, system: String, messages: [ChatMessage], tools: [ToolSpec] = [], executor: ToolExecutor? = nil) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.executor = executor
    }
}

/// Why the model stopped.
public enum StopReason: String, Sendable, Equatable {
    case endTurn
    case toolUse
    case maxTokens
    case refusal
    case other
}

/// What a provider streams back while answering.
public enum ChatStreamEvent: Sendable {
    case textDelta(String)
    /// The model started a tool call. Shown as activity while arguments stream.
    case toolCallStarted(name: String)
    /// The finished assistant message, including tool calls and provider state.
    case completed(ChatMessage, StopReason)
}
