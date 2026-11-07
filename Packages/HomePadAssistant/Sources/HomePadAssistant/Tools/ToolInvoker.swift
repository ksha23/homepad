import Foundation
import HomePadCore

/// Runs tool calls safely: unknown tools, bad JSON, missing required fields,
/// locked personal tools and sensitive foreign tools are all handled here
/// before any handler runs.
@MainActor
struct ToolInvoker {
    let tools: [AssistantTool]
    let household: Household
    let confirmations: ConfirmationCenter
    /// The assistant's own tools ask their own precise questions.
    let selfConfirmingTools: Set<String>

    func invoke(_ call: ToolCall) async -> ToolResult {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return failure(call, "There is no tool named \(call.name).")
        }
        if tool.requiresRecognizedMember, !household.isPersonalContentUnlocked {
            return failure(call, "This needs a recognized household member. Ask them to look at the screen.")
        }
        let arguments: JSONValue
        do {
            arguments = call.arguments.trimmingCharacters(in: .whitespaces).isEmpty ? [:] : try JSONValue.parse(call.arguments)
        } catch {
            return failure(call, JSONValue.object(["INVALID_JSON": .string(call.arguments)]).jsonString())
        }
        if let problem = ToolArgumentValidator.problem(with: arguments, schema: tool.parameters) {
            return failure(call, problem)
        }
        if !selfConfirmingTools.contains(tool.name), let question = SensitiveActionPolicy.question(forToolNamed: tool.name) {
            guard await confirmations.confirm(question) else {
                return ToolResult(callID: call.id, name: call.name, content: "The person said no, so nothing was done.")
            }
        }
        do {
            let output = try await tool.handler(arguments)
            return ToolResult(callID: call.id, name: call.name, content: output)
        } catch {
            return failure(call, error.localizedDescription)
        }
    }

    private func failure(_ call: ToolCall, _ message: String) -> ToolResult {
        ToolResult(callID: call.id, name: call.name, content: message, isError: true)
    }
}

/// A light JSON Schema check: arguments must be an object with every required key.
/// Streamed arguments can arrive truncated, and this catches that before a handler runs.
enum ToolArgumentValidator {
    static func problem(with arguments: JSONValue, schema: JSONValue) -> String? {
        guard let object = arguments.objectValue else { return "Arguments must be a JSON object." }
        let required = schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let missing = required.filter { object[$0] == nil || object[$0] == .null }
        guard missing.isEmpty else { return "Missing required argument: \(missing.joined(separator: ", "))." }
        return nil
    }
}
