import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// A fake provider that answers every request with a fixed reply.
@MainActor
final class CannedAssistant: AssistantService {
    var phase: AssistantPhase = .idle
    var liveTranscript = ""
    var activeProviderName: String
    var isConfigured: Bool { activeProviderName != "None" }
    let reply: String
    private(set) var prompts: [String] = []

    init(name: String = "Claude", reply: String) {
        activeProviderName = name
        self.reply = reply
    }

    func ask(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        prompts.append(request.text)
        let reply = reply
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(reply))
            continuation.yield(.finished(fullText: reply))
            continuation.finish()
        }
    }

    func startListening() {}
    func stopListening() {}
    func cancel() {}
}

@MainActor
@Suite struct TextImportTests {
    static let scannedPage = """
    Lemon Ricotta Pancakes
    Serves 4
    Prep time: 10 min
    Cook time: 15 minutes
    Ingredients
    1 1/2 cups flour
    2 tbsp sugar
    1 cup ricotta
    2 eggs
    Zest of 1 lemon
    Method
    1. Whisk the flour and sugar in a large
    bowl.
    2. Beat the ricotta, eggs and lemon zest, then fold
    into the flour.
    3. Cook on a buttered griddle, 2 to 3 minutes per side.
    """

    @Test func heuristicsReadAScannedPage() throws {
        let recipe = try #require(HeuristicRecipeParser.parse(lines: Self.scannedPage.components(separatedBy: .newlines), title: nil))
        #expect(recipe.title == "Lemon Ricotta Pancakes")
        #expect(recipe.servings == 4)
        #expect(recipe.prepTime == 600)
        #expect(recipe.cookTime == 900)
        #expect(recipe.ingredients == ["1 1/2 cups flour", "2 tbsp sugar", "1 cup ricotta", "2 eggs", "Zest of 1 lemon"])
        #expect(recipe.steps.map(\.text) == [
            "Whisk the flour and sugar in a large bowl.",
            "Beat the ricotta, eggs and lemon zest, then fold into the flour.",
            "Cook on a buttered griddle, 2 to 3 minutes per side.",
        ])
    }

    @Test func heuristicsWithoutHeadings() throws {
        let text = """
        Garlic Butter
        4 tablespoons butter, softened
        2 cloves garlic, grated
        1 tablespoon parsley
        Mash everything together with a fork until evenly mixed.
        Chill for 20 minutes before serving.
        """
        let recipe = try #require(HeuristicRecipeParser.parse(lines: text.components(separatedBy: .newlines), title: nil))
        #expect(recipe.title == "Garlic Butter")
        #expect(recipe.ingredients.count == 3)
        #expect(recipe.steps.count == 2)
    }

    @Test func heuristicsRejectProse() {
        let text = "Dear diary,\nToday I went to the market and bought nothing at all.\nIt was a lovely day."
        #expect(HeuristicRecipeParser.parse(lines: text.components(separatedBy: .newlines), title: nil) == nil)
    }

    @Test func assistantJSONIsPreferredWhenConfigured() async throws {
        let reply = """
        ```json
        {"title": "Lemon Ricotta Pancakes", "summary": null, "servings": 4, "prepMinutes": 10, "cookMinutes": 15,
         "totalMinutes": null, "ingredients": ["1 1/2 cups flour", "1 cup ricotta"],
         "sections": [{"title": null, "steps": ["Whisk.", "Cook 2 to 3 minutes per side."]}]}
        ```
        """
        let assistant = CannedAssistant(reply: reply)
        let recipe = try await RecipeImporter().importRecipe(fromText: Self.scannedPage, assistant: assistant)
        #expect(recipe.title == "Lemon Ricotta Pancakes")
        #expect(recipe.prepTime == 600)
        #expect(recipe.steps.count == 2)
        #expect(assistant.prompts.first?.contains("Reply with JSON only") == true)
        #expect(assistant.prompts.first?.contains("Zest of 1 lemon") == true)
    }

    @Test func badAssistantReplyFallsBackToHeuristics() async throws {
        let assistant = CannedAssistant(reply: "Sorry, I can't help with that.")
        let recipe = try await RecipeImporter().importRecipe(fromText: Self.scannedPage, assistant: assistant)
        #expect(recipe.ingredients.count == 5)
    }

    @Test func unconfiguredAssistantIsSkipped() async throws {
        let assistant = CannedAssistant(name: "None", reply: "{}")
        _ = try await RecipeImporter().importRecipe(fromText: Self.scannedPage, assistant: assistant)
        #expect(assistant.prompts.isEmpty)
    }

    @Test func emptyTextThrows() async {
        await #expect(throws: RecipeImportError.self) {
            try await RecipeImporter().importRecipe(fromText: "  \n ", assistant: nil)
        }
    }
}
