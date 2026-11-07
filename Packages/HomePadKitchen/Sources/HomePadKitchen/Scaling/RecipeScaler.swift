import Foundation

/// How a recipe's amounts should be shown: scaled to a number of servings and
/// in a unit system.
public struct AmountAdjustment: Hashable, Sendable {
    /// Multiplier on every amount, for example 1.5 to go from 4 to 6 servings.
    public var factor: Double
    public var system: UnitSystem

    public init(factor: Double = 1, system: UnitSystem = .original) {
        self.factor = factor
        self.system = system
    }

    /// True when amounts show exactly as the recipe wrote them.
    public var isIdentity: Bool { abs(factor - 1) < 0.0001 && system == .original }

    /// The factor that turns `base` servings into `target` servings.
    public static func factor(from base: Int?, to target: Int) -> Double {
        guard let base, base > 0, target > 0 else { return 1 }
        return Double(target) / Double(base)
    }
}

/// An ingredient ready to show: the amount (orange in the UI) and the rest.
public struct DisplayIngredient: Hashable, Sendable {
    public var amount: String?
    public var name: String

    /// The full line, for reminders and the assistant.
    public var text: String {
        [amount, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Scales and converts amounts in ingredient lines.
public enum RecipeScaler {
    /// One amount after scaling and conversion.
    public static func adjust(_ amount: IngredientAmount, with adjustment: AmountAdjustment) -> IngredientAmount {
        var scaled = amount
        scaled.quantity = amount.quantity.multiplied(by: adjustment.factor)
        if let alternate = amount.alternate {
            scaled.alternate?.quantity = alternate.quantity.multiplied(by: adjustment.factor)
        }
        return UnitConverter.convert(scaled, to: adjustment.system)
    }

    /// An ingredient line for display. Unchanged amounts keep the author's wording.
    public static func display(_ ingredient: ParsedIngredient, with adjustment: AmountAdjustment) -> DisplayIngredient {
        guard let amount = ingredient.amount else {
            return DisplayIngredient(amount: nil, name: ingredient.name)
        }
        if adjustment.isIdentity {
            return DisplayIngredient(amount: ingredient.writtenAmount, name: ingredient.name)
        }
        let adjusted = adjust(amount, with: adjustment)
        return DisplayIngredient(amount: QuantityFormatter.string(for: adjusted), name: ingredient.name)
    }

    /// A raw ingredient line scaled and converted, as one string.
    public static func scaledLine(_ line: String, with adjustment: AmountAdjustment) -> String {
        display(IngredientParser.parse(line), with: adjustment).text
    }
}
