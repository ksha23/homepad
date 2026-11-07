import Foundation
import HomePadCore

/// Asks the configured AI provider to structure scanned recipe text as strict JSON.
/// Returns nil when no provider is set up or the answer is not usable, so the
/// caller can fall back to `HeuristicRecipeParser`. The request is a
/// self-contained text task: the provider gets the prompt and the text, with
/// no tools, no chat history and nothing about the household.
@MainActor
enum AssistantRecipeStructurer {
    static func isAvailable(_ assistant: any AssistantService) -> Bool {
        assistant.isConfigured
    }

    static func structure(_ text: String, with assistant: any AssistantService, timeout: Duration = .seconds(45)) async -> Recipe? {
        guard isAvailable(assistant) else { return nil }
        let answer = await assistant.answerText(to: .textTask(prompt(for: text)), timeout: timeout)
        return answer.flatMap(decode)
    }

    static func prompt(for text: String) -> String {
        """
        Convert the recipe text below into JSON. Reply with JSON only, no markdown and no commentary.
        Use exactly this shape:
        {"title": string, "summary": string or null, "servings": integer or null,
         "prepMinutes": number or null, "cookMinutes": number or null, "totalMinutes": number or null,
         "ingredients": [string], "sections": [{"title": string or null, "steps": [string]}]}
        Keep each ingredient line with its amount and unit as written. One step per instruction.
        Fix obvious scanning errors but do not invent ingredients or steps.

        Recipe text:
        \(text)
        """
    }

    /// Reads a reply into a recipe, tolerating code fences and text around the JSON.
    static func decode(_ reply: String) -> Recipe? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let json = try? JSONValue.parse(String(reply[start...end])),
              let title = json["title"]?.stringValue, !title.isEmpty else { return nil }

        let ingredients = json["ingredients"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let sections: [RecipeSection] = json["sections"]?.arrayValue?.compactMap { section in
            let steps = section["steps"]?.arrayValue?.compactMap(\.stringValue).filter { !$0.isEmpty } ?? []
            return steps.isEmpty ? nil : RecipeSection(title: section["title"]?.stringValue, steps: steps)
        } ?? []
        let recipe = Recipe(
            title: title,
            summary: json["summary"]?.stringValue,
            prepTime: minutes(json["prepMinutes"]),
            cookTime: minutes(json["cookMinutes"]),
            totalTime: minutes(json["totalMinutes"]),
            servings: json["servings"]?.intValue,
            ingredients: ingredients,
            sections: sections
        )
        return recipe.isUsable && !ingredients.isEmpty ? recipe : nil
    }

    private static func minutes(_ value: JSONValue?) -> TimeInterval? {
        guard let minutes = value?.doubleValue, minutes > 0 else { return nil }
        return minutes * 60
    }

}
