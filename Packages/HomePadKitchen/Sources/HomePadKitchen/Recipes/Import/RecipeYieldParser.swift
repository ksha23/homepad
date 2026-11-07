import Foundation
import HomePadCore

/// Reads `recipeYield`, which sites write as `4`, `"4"`, `"4 servings"`,
/// `"Serves 4-6"`, `"Makes 24 cookies"` or arrays like `["4", "4 servings"]`.
enum RecipeYieldParser {
    private static let firstNumber = NSRegularExpression(compiling: #"\d+"#)

    /// Servings as a number and the most descriptive wording.
    static func parse(_ value: JSONValue?) -> (servings: Int?, text: String?) {
        let values: [String]
        switch value {
        case .number(let number): values = [String(Int(number))]
        case .string(let string): values = [string]
        case .array(let items): values = items.compactMap { $0.stringValue ?? $0.doubleValue.map { String(Int($0)) } }
        default: values = []
        }
        let cleaned = values.map(HTMLText.plainText).filter { !$0.isEmpty }
        let servings = cleaned.lazy.compactMap(firstInteger).first
        // Prefer wording with letters ("4 servings") over a bare number.
        let text = cleaned.first { $0.contains(where: \.isLetter) } ?? cleaned.first
        return (servings, text)
    }

    /// Servings from free text such as "Serves 4 to 6".
    static func servings(in text: String) -> Int? {
        firstInteger(text)
    }

    private static func firstInteger(_ text: String) -> Int? {
        guard let match = firstNumber.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let value = match.group(0, in: text).flatMap(Int.init), value > 0, value < 1000 else { return nil }
        return value
    }
}
