import Foundation
import Testing
@testable import HomePadKitchen

/// Fixtures mimic the structures of real recipe pages: a WordPress plugin graph,
/// a big publisher's top-level array, a newspaper-style single object, a nested
/// WebPage mainEntity, a hand-written blog with invalid JSON, nested HowTo shapes,
/// microdata, and a page without any structured data.
@Suite struct RecipePageParserTests {
    private func parse(_ name: String, url: String = "https://example.com/recipe/") throws -> Recipe {
        let fileURL = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        let html = try String(contentsOf: fileURL, encoding: .utf8)
        return try RecipePageParser.parse(html: html, pageURL: URL(string: url))
    }

    @Test func wordpressGraphWithSectionsAndReferences() throws {
        let recipe = try parse("wordpress-yoast-graph", url: "https://weeknightpantry.example/creamy-tomato-pasta/")
        #expect(recipe.title == "Creamy Tomato Pasta")
        #expect(recipe.summary == "A 30 minute pasta with a silky tomato cream sauce.")
        #expect(recipe.source == "Weeknight Pantry")
        #expect(recipe.imageURL?.absoluteString == "https://weeknightpantry.example/wp-content/uploads/2026/03/tomato-pasta-1200x800.jpg")
        #expect(recipe.prepTime == 600)
        #expect(recipe.cookTime == 1200)
        #expect(recipe.totalTime == 1800)
        #expect(recipe.servings == 4)
        #expect(recipe.yieldText == "4 servings")
        #expect(recipe.ingredients.count == 7)
        #expect(recipe.ingredients[3] == "1 (28 oz) can crushed tomatoes")
        #expect(recipe.sections.map(\.title) == ["For the sauce", "To finish"])
        #expect(recipe.sections.map(\.steps.count) == [2, 2])
        // The full text wins over the truncated step name.
        #expect(recipe.steps[0].text == "Warm the oil in a large skillet over medium heat. Add the garlic and cook for 30 seconds.")
        #expect(recipe.steps[2].sectionTitle == "To finish")
        #expect(recipe.tags == ["Dinner", "Italian", "pasta", "weeknight", "tomato"])
    }

    @Test func topLevelArrayWithTypeArrayAndImageObject() throws {
        let recipe = try parse("dotdash-array")
        #expect(recipe.title == "Classic Meatloaf")
        #expect(recipe.source == "Recipe Example")
        #expect(recipe.imageURL?.absoluteString == "https://recipes.example/thmb/meatloaf-1500x1125.jpg")
        #expect(recipe.servings == 8)
        #expect(recipe.totalTime == 4800)
        #expect(recipe.cookTime == 3600)
        #expect(recipe.ingredients.first == "1 ½ pounds ground beef")
        #expect(recipe.steps.count == 4)
        #expect(recipe.steps[0].text == "Preheat the oven to 350 degrees F (175 degrees C).")
    }

    @Test func singleObjectWithEntitiesLinksAndAuthorArray() throws {
        let recipe = try parse("nyt-style")
        #expect(recipe.title == "Lemony White Bean Soup With Turkey and Greens")
        #expect(recipe.summary == "This soup is a weeknight staple & freezes well.")
        #expect(recipe.source == "Cooking Example")
        // The largest declared ImageObject.
        #expect(recipe.imageURL?.absoluteString == "https://static.example/images/2026/01/soup-threeByTwoMediumAt2X.jpg")
        #expect(recipe.servings == 4)
        #expect(recipe.yieldText == "4 to 6 servings")
        #expect(recipe.totalTime == 4500)
        #expect(recipe.prepTime == nil)
        #expect(recipe.steps[0].text == "Heat the oil in a large pot over medium-high. Add the onion and cook until it’s golden, 5 to 7 minutes.")
        #expect(recipe.steps[1].text == "Add the turkey and cook, breaking it up, until browned, about 8 minutes. See our browning guide.")
        #expect(recipe.tags.contains("soups"))
    }

    @Test func recipeNestedUnderWebPageMainEntity() throws {
        let recipe = try parse("bbc-style")
        #expect(recipe.title == "Easy pancakes")
        #expect(recipe.summary == "Learn how to make simple pancakes with this easy recipe.")
        #expect(recipe.servings == 12)
        #expect(recipe.prepTime == 600)
        #expect(recipe.totalTime == 1800)
        #expect(recipe.ingredients[0] == "100g plain flour")
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[1].text.hasPrefix("Set aside for 30 mins"))
        #expect(recipe.imageURL?.absoluteString == "https://images.example/recipes/easy-pancakes.jpg")
    }

    @Test func messyBlogJSONIsRepaired() throws {
        let recipe = try parse("blog-messy", url: "https://grandmasbakes.example/cookies/")
        #expect(recipe.title == "Grandma's Chewy Chocolate Chip Cookies")
        #expect(recipe.summary == "Crisp edges, chewy middles.")
        #expect(recipe.source == "Grandma June")
        #expect(recipe.imageURL?.absoluteString == "https://grandmasbakes.example/images/cookies.jpg")
        #expect(recipe.yieldText == "Makes 24 cookies")
        #expect(recipe.servings == 24)
        #expect(recipe.prepTime == 1800)
        #expect(recipe.cookTime == 720)
        #expect(recipe.ingredients.count == 6)
        #expect(recipe.steps.map(\.text) == [
            "Heat oven to 375°F.",
            "Cream the butter and sugar until fluffy, 2 to 3 minutes.",
            "Beat in the eggs, then stir in the flour and baking soda.",
            "Fold in the chips and scoop onto sheets.",
            "Bake 9 to 11 minutes, until golden at the edges.",
        ])
    }

    @Test func nestedHowToShapesFlattenInOrder() throws {
        let recipe = try parse("howto-nested")
        #expect(recipe.title == "Weeknight Chili")
        #expect(recipe.servings == 6)
        #expect(recipe.imageURL?.absoluteString == "https://soups.example/wp-content/uploads/chili.jpg")
        #expect(recipe.ingredients.count == 5)
        #expect(recipe.sections.count == 1)
        #expect(recipe.steps.map(\.text) == [
            "Heat the oil in a Dutch oven over medium heat.",
            "Add the onion and cook 5 minutes.",
            "Add the beef and brown it, 6 to 8 minutes.",
            "Stir in the chili powder and cook 1 minute.",
            "Add the tomatoes and simmer 25 minutes.",
            "Serve with your favorite toppings.",
        ])
    }

    @Test func microdataFallback() throws {
        let recipe = try parse("microdata", url: "https://oldbox.example/banana-bread")
        #expect(recipe.title == "Simple Banana Bread")
        #expect(recipe.summary == "Moist and easy.")
        #expect(recipe.imageURL?.absoluteString == "https://oldbox.example/photos/banana-bread.jpg")
        #expect(recipe.prepTime == 900)
        #expect(recipe.cookTime == 3600)
        #expect(recipe.yieldText == "1 loaf (10 slices)")
        #expect(recipe.ingredients == ["3 ripe bananas, mashed", "1/3 cup melted butter", "3/4 cup sugar", "1 1/2 cups flour"])
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[0].text == "Heat the oven to 350°F and butter a loaf pan.")
        #expect(recipe.source == "oldbox.example")
    }

    @Test func headingsAndListsWithoutStructuredData() throws {
        let recipe = try parse("plain-page", url: "https://notes.example/pickled-onions")
        #expect(recipe.title == "Quick Pickled Onions")
        #expect(recipe.source == "Small Kitchen Notes")
        #expect(recipe.imageURL?.absoluteString == "https://notes.example/onions.jpg")
        #expect(recipe.servings == 8)
        #expect(recipe.ingredients.count == 5)
        #expect(recipe.ingredients[1] == "1/2 cup apple cider vinegar")
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[2].text == "Pour over the onion and let stand 30 minutes before serving.")
        #expect(recipe.sourceURL?.absoluteString == "https://notes.example/pickled-onions")
    }

    @Test func pageWithoutRecipeThrows() throws {
        #expect(throws: RecipeImportError.self) { try parse("no-recipe") }
    }

    @Test func importerUsesFetcher() async throws {
        struct FixtureFetcher: RecipePageFetching {
            func html(for url: URL) async throws -> String {
                let fileURL = Bundle.module.url(forResource: "dotdash-array", withExtension: "html", subdirectory: "Fixtures")!
                return try String(contentsOf: fileURL, encoding: .utf8)
            }
        }
        let recipe = try await RecipeImporter(fetcher: FixtureFetcher()).importRecipe(from: "Look at this https://recipes.example/recipe/meatloaf/ yum")
        #expect(recipe.title == "Classic Meatloaf")
        #expect(recipe.sourceURL?.host() == "recipes.example")
    }

    @Test func linkDetection() {
        #expect(RecipeImporter.url(from: "https://a.example/x")?.absoluteString == "https://a.example/x")
        #expect(RecipeImporter.url(from: "a.example/x")?.absoluteString == "https://a.example/x")
        #expect(RecipeImporter.url(from: "Check this out: http://b.example/pie !")?.absoluteString == "http://b.example/pie")
        #expect(RecipeImporter.url(from: "two cups of flour") == nil)
    }
}
