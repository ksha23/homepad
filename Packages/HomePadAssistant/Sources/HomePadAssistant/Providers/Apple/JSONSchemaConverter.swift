import Foundation
import FoundationModels
import HomePadCore

/// Converts the JSON Schema that `AssistantTool` uses into a Foundation Models
/// `GenerationSchema`, so every registered tool works with the on-device model.
///
/// Supported: objects (required and optional properties), arrays, strings,
/// string enums, integers, numbers and booleans. Anything else becomes a string.
enum JSONSchemaConverter {
    static func generationSchema(for json: JSONValue, name: String) throws -> GenerationSchema {
        try GenerationSchema(root: dynamicSchema(for: json, name: name), dependencies: [])
    }

    static func dynamicSchema(for json: JSONValue, name: String) -> DynamicGenerationSchema {
        let description = json["description"]?.stringValue
        if let choices = json["enum"]?.arrayValue?.compactMap(\.stringValue), !choices.isEmpty {
            return DynamicGenerationSchema(name: name, description: description, anyOf: choices)
        }
        switch json["type"]?.stringValue {
        case "object":
            let properties = json["properties"]?.objectValue ?? [:]
            let required = Set(json["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            return DynamicGenerationSchema(
                name: name, description: description,
                properties: properties.keys.sorted().map { key in
                    let child = properties[key] ?? [:]
                    return DynamicGenerationSchema.Property(
                        name: key, description: child["description"]?.stringValue,
                        schema: dynamicSchema(for: child, name: "\(name)_\(key)"),
                        isOptional: !required.contains(key)
                    )
                }
            )
        case "array":
            return DynamicGenerationSchema(arrayOf: dynamicSchema(for: json["items"] ?? ["type": "string"], name: "\(name)_item"))
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        default:
            return DynamicGenerationSchema(type: String.self)
        }
    }
}
