import Foundation

/// Plain text for the system share sheet: the link when there is one, otherwise
/// the whole recipe so it can go to Messages, Notes or Mail.
enum RecipeShareText {
    static func text(for recipe: Recipe, ingredients: [String]? = nil) -> String {
        if let url = recipe.sourceURL, ingredients == nil {
            return "\(recipe.title)\n\(url.absoluteString)"
        }
        var lines = [recipe.title]
        let meta = RecipeMetadata.line(for: recipe)
        if !meta.isEmpty { lines.append(meta) }
        lines.append("")
        lines.append("Ingredients")
        lines += (ingredients ?? recipe.ingredients).map { "• " + $0 }
        if ingredients == nil {
            lines.append("")
            lines.append("Steps")
            lines += recipe.steps.map { "\($0.number). \($0.text)" }
        }
        if let url = recipe.sourceURL { lines += ["", url.absoluteString] }
        return lines.joined(separator: "\n")
    }
}
