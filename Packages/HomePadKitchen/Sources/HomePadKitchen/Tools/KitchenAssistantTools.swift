import Foundation
import HomePadCore

/// Assistant tools for recipes and cooking mode, plus `RecipeCatalogTools` for
/// finding new recipes and `MealPlanTools` for the week's plan. The generic
/// start, list and cancel timer tools belong to the assistant module, over
/// `services.timers`.
@MainActor
enum KitchenAssistantTools {
    static func make(context: KitchenContext) -> [AssistantTool] {
        [openRecipe(context), nextStep(context), previousStep(context),
         readCurrentStep(context), readIngredients(context), scaleRecipe(context)]
            + RecipeCatalogTools.make(context: context)
            + MealPlanTools.make(context: context)
    }

    private static let noRecipe = "No recipe is open. Use open_recipe with a recipe name first."

    private static func openRecipe(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(
            name: "open_recipe",
            description: "Open a saved recipe on screen by name, showing its card with ingredients and a Start Cooking button.",
            parameters: Schema.object(["name": Schema.string("The recipe name, for example \"french toast\".")], required: ["name"])
        ) { arguments in
            let name = arguments["name"]?.stringValue ?? ""
            guard let recipe = context.library.find(named: name) else {
                let titles = context.library.recipes.prefix(12).map(\.title).joined(separator: ", ")
                return "No saved recipe matches \"\(name)\". Saved recipes: \(titles). To find one online, use search_recipes."
            }
            context.open(recipe, bringToFront: true)
            let facts = RecipeMetadata.parts(for: recipe).details.joined(separator: ", ")
            return "Opened \(recipe.title)\(facts.isEmpty ? "" : " (\(facts))"). It has \(recipe.steps.count) steps."
        }
    }

    private static func nextStep(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(name: "cooking_next_step",
                      description: "Go to the next step of the open recipe in cooking mode and return its text to read aloud. Starts cooking mode at step 1 if it is not running.") { _ in
            guard let session = context.session else { return noRecipe }
            if context.screen != .cooking {
                context.open(session.recipe, bringToFront: true)
                context.startCooking()
                return session.spokenStep()
            }
            guard session.next() else { return "That was the last step. \(session.spokenStep())" }
            return session.spokenStep()
        }
    }

    private static func previousStep(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(name: "cooking_previous_step",
                      description: "Go back one step in cooking mode and return that step's text.") { _ in
            guard let session = context.session else { return noRecipe }
            guard session.previous() else { return "Already at the first step. \(session.spokenStep())" }
            return session.spokenStep()
        }
    }

    private static func readCurrentStep(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(name: "read_current_step",
                      description: "Return the text of the current cooking step, with amounts scaled to the chosen servings.") { _ in
            context.session?.spokenStep() ?? noRecipe
        }
    }

    private static func readIngredients(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(name: "read_ingredients",
                      description: "List the open recipe's ingredients, scaled to the chosen servings and units.") { _ in
            guard let session = context.session else { return noRecipe }
            return ingredientSummary(session)
        }
    }

    private static func scaleRecipe(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(
            name: "scale_recipe",
            description: "Scale the open recipe to a number of servings. Returns the scaled ingredients.",
            parameters: Schema.object(["servings": Schema.integer("How many servings to make, 1 to 48.")], required: ["servings"])
        ) { arguments in
            guard let session = context.session else { return noRecipe }
            guard session.canScale else { return "\(session.recipe.title) does not say how many it serves, so it cannot be scaled." }
            guard let servings = arguments["servings"]?.intValue, (1...48).contains(servings) else {
                return "Servings must be a whole number from 1 to 48."
            }
            session.servings = servings
            return ingredientSummary(session)
        }
    }

    private static func ingredientSummary(_ session: RecipeSession) -> String {
        let lines = session.displayIngredients.map(\.text).joined(separator: "; ")
        return "\(session.recipe.title) for \(session.servings): \(lines)."
    }
}
