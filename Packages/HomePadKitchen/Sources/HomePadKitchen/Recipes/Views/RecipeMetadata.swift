import Foundation

/// The one-line facts under a recipe title: "Home Cookbook · 35 min · Serves 4".
enum RecipeMetadata {
    static func parts(for recipe: Recipe, servings: Int? = nil) -> (source: String?, details: [String]) {
        var details: [String] = []
        if let time = recipe.displayTime { details.append(TimerFormat.spoken(time)) }
        if let servings = servings ?? recipe.servings {
            details.append("Serves \(servings)")
        } else if let yield = recipe.yieldText {
            details.append(yield)
        }
        return (recipe.source, details)
    }

    static func line(for recipe: Recipe) -> String {
        let parts = parts(for: recipe)
        return ([parts.source].compactMap { $0 } + parts.details).joined(separator: " · ")
    }
}
