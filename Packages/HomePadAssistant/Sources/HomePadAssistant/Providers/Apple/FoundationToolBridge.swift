import Foundation
import FoundationModels

/// Wraps one HomePad tool as a Foundation Models `Tool`. Arguments arrive as
/// `GeneratedContent` matching the converted schema and go to the engine's
/// executor as JSON, so confirmations and cards work the same as with cloud models.
struct FoundationToolBridge: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    private let executor: ToolExecutor

    init(spec: ToolSpec, executor: @escaping ToolExecutor) throws {
        self.name = spec.name
        self.description = spec.description
        self.parameters = try JSONSchemaConverter.generationSchema(for: spec.parameters, name: spec.name)
        self.executor = executor
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let call = ToolCall(id: UUID().uuidString, name: name, arguments: arguments.jsonString)
        return await executor(call).content
    }
}
