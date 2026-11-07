import Foundation
import HomePadCore

/// Assistant tools for finding new recipes: search the catalog, preview one
/// result, save one, and import a link. Results show in the Recipes app as
/// well, and every save goes through `KitchenContext.save`, the same path as
/// the library's field and the preview sheet.
@MainActor
enum RecipeCatalogTools {
    static func make(context: KitchenContext) -> [AssistantTool] {
        [searchRecipes(context), previewRecipe(context), saveRecipe(context), importRecipeLink(context)]
    }

    /// How a tool names one result: its number in the last search, or a name.
    private static let choice: [String: JSONValue] = [
        "number": Schema.integer("The result's number from the last search_recipes answer, starting at 1."),
        "name": Schema.string("Or the recipe's name, for example \"katsu chicken curry\"."),
    ]

    static func searchRecipes(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(
            name: "search_recipes",
            description: """
            Find new recipes online, for example "find a chicken curry recipe" or "what can I make with lentils". \
            Shows the results in the Recipes app and returns them numbered. Use open_recipe for recipes already saved.
            """,
            parameters: Schema.object(["query": Schema.string("A dish or a main ingredient, for example \"chicken curry\" or \"lentils\".")],
                                      required: ["query"])
        ) { arguments in
            let query = arguments["query"]?.stringValue ?? ""
            let results = await context.search.run(query)
            context.showLibrary()
            if case .failed(let message, _) = context.search.phase { return message }
            let catalog = context.catalog.name
            guard !results.isEmpty else {
                return "\(catalog) has no recipes for \"\(query)\". Suggest searching for one main ingredient instead."
            }
            let listed = results.prefix(8).enumerated().map { index, result in "\(index + 1). \(describe(result))" }
            return "Found \(results.count) on \(catalog), now on screen: \(listed.joined(separator: " ")) "
                + "Offer to save one. Call save_recipe only after the person picks one or agrees."
        }
    }

    static func previewRecipe(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(
            name: "preview_recipe",
            description: "Show one recipe from the last search_recipes results on screen, without saving it, and return its ingredients and steps to read.",
            parameters: Schema.object(choice)
        ) { arguments in
            guard let result = pick(arguments, in: context) else { return noChoice(context) }
            context.preview(result, bringToFront: true)
            let recipe = result.recipe
            let steps = recipe.steps.map { "\($0.number). \($0.text)" }.joined(separator: " ")
            return "Showing \(describe(result)) Ingredients: \(recipe.ingredients.joined(separator: "; ")). Steps: \(steps)"
        }
    }

    static func saveRecipe(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(
            name: "save_recipe",
            description: """
            Save a recipe found with search_recipes, or the one being previewed, to My Recipes and open it. \
            Call it only after the person asks to save it or says yes when you offer.
            """,
            parameters: Schema.object(choice)
        ) { arguments in
            guard let result = pick(arguments, in: context) else { return noChoice(context) }
            context.previewedResult = nil
            if let saved = context.savedRecipe(for: result) {
                context.open(saved, bringToFront: true)
                return "\(saved.title) is already in My Recipes, so it is open now."
            }
            let saved = context.save(result.recipe)
            return "Saved \(saved.title) to My Recipes and opened it. It has \(saved.ingredients.count) ingredients and \(saved.steps.count) steps."
        }
    }

    static func importRecipeLink(_ context: KitchenContext) -> AssistantTool {
        AssistantTool(
            name: "import_recipe_link",
            description: "Add the recipe from a web page link to My Recipes and open it, for example \"add the recipe from this link\".",
            parameters: Schema.object(["url": Schema.string("The recipe page's web address.")], required: ["url"])
        ) { arguments in
            let link = arguments["url"]?.stringValue ?? ""
            guard let recipe = await context.importRecipe(link: link) else {
                if case .failed(let message) = context.importStatus { return message }
                return "That recipe could not be added."
            }
            let source = recipe.source.map { " from \($0)" } ?? ""
            return "Added \(recipe.title)\(source) to My Recipes and opened it. It has \(recipe.ingredients.count) ingredients and \(recipe.steps.count) steps."
        }
    }

    // MARK: Helpers

    /// The result a tool call means: by number, else by name among the results
    /// and Discover, else the one being previewed, else the only result.
    static func pick(_ arguments: JSONValue, in context: KitchenContext) -> CatalogRecipe? {
        let results = context.search.results
        if let number = arguments["number"]?.intValue {
            return results.indices.contains(number - 1) ? results[number - 1] : nil
        }
        if let name = arguments["name"]?.stringValue?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return bestMatch(for: name, in: results + context.discovery.picks + [context.previewedResult].compactMap { $0 })
        }
        return context.previewedResult ?? (results.count == 1 ? results.first : nil)
    }

    private static func bestMatch(for name: String, in candidates: [CatalogRecipe]) -> CatalogRecipe? {
        let needle = name.lowercased()
        if let exact = candidates.first(where: { $0.recipe.title.lowercased() == needle }) { return exact }
        let words = MealDBCatalog.searchWords(in: needle).filter { $0.count > 2 }
        let scored = candidates.map { candidate in
            (candidate, words.filter { candidate.recipe.title.lowercased().contains($0) }.count)
        }
        return scored.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    private static func noChoice(_ context: KitchenContext) -> String {
        let results = context.search.results
        guard !results.isEmpty else { return "There are no search results yet. Call search_recipes first." }
        return "Say which result: a number from 1 to \(results.count), or its name."
    }

    /// "Katsu Chicken curry (Japanese · Chicken, 45 min, 16 ingredients)."
    static func describe(_ result: CatalogRecipe) -> String {
        var facts = [result.kindLine].compactMap { $0 }
        if let time = result.recipe.displayTime { facts.append(TimerFormat.spoken(time)) }
        facts.append("\(result.recipe.ingredients.count) ingredients")
        return "\(result.recipe.title) (\(facts.joined(separator: ", ")))."
    }
}
