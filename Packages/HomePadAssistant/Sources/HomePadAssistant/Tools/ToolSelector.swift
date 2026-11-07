import Foundation
import HomePadCore

/// Picks the most relevant tools for a request when a model can only take a
/// few (the on-device model has a small context). Core home tools always stay.
enum ToolSelector {
    static let alwaysInclude: Set<String> = ["control_device", "get_time", "get_weather"]

    static func select(_ tools: [AssistantTool], for request: String, limit: Int) -> [AssistantTool] {
        guard tools.count > limit else { return tools }
        let words = Set(tokens(request))
        let scored = tools.map { tool -> (AssistantTool, Int) in
            if alwaysInclude.contains(tool.name) { return (tool, Int.max) }
            let toolWords = Set(tokens(tool.name.replacingOccurrences(of: "_", with: " ") + " " + tool.description))
            return (tool, words.intersection(toolWords).count)
        }
        return scored.enumerated()
            .sorted { lhs, rhs in lhs.element.1 != rhs.element.1 ? lhs.element.1 > rhs.element.1 : lhs.offset < rhs.offset }
            .prefix(limit)
            .map(\.element.0)
    }

    /// Lowercased words of three or more letters, with a trailing plural "s" removed.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
            .map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    }
}
