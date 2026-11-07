import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// What the Recipes app tells the assistant, so "add these to my shopping list"
/// and "what's next" work on the recipe on screen.
@MainActor
@Suite struct RecipeScreenContextTests {
    private let context = KitchenContext(
        services: nil, library: RecipeLibrary(directory: FileManager.default.temporaryDirectory.appending(path: "kitchen-screen-\(UUID().uuidString)")))
    private let recipe = Recipe(title: "Shakshuka", servings: 4, ingredients: ["6 eggs", "1 onion", "2 tbsp olive oil"],
                                sections: [RecipeSection(steps: ["Soften the onion in the oil.", "Crack in the eggs and cover."])])

    private var summary: String? {
        RecipeScreenContext.summary(of: context)
    }

    @Test func theLibrarySaysNothing() {
        #expect(summary == nil)
    }

    @Test func theCardListsTheIngredientsAsShown() throws {
        context.open(recipe)
        #expect(summary == "The recipe card for Shakshuka. Ingredients for 4 servings: 6 eggs; 1 onion; 2 tbsp olive oil.")
        let session = try #require(context.session)
        session.servings = 2
        session.toggleIngredient(0)
        #expect(summary == "The recipe card for Shakshuka. Ingredients for 2 servings: 3 eggs; ½ onion; 1 tbsp olive oil."
            + " Ticked off as on hand: 3 eggs.")
    }

    @Test func cookingModeSaysTheStep() throws {
        context.open(recipe)
        context.startCooking()
        try #require(context.session).next()
        #expect(summary?.hasPrefix("Cooking mode for Shakshuka. Step 2 of 2. Crack in the eggs and cover. Ingredients for 4 servings:") == true)
    }

    @Test func itIsRegisteredForTheRecipesApp() {
        let provider = RecipeScreenContext.provider(context: context)
        #expect(provider.appID == KitchenModule.recipesAppID)
        #expect(!provider.isPersonal)
    }
}
