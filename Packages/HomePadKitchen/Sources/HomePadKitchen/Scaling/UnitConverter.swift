import Foundation

/// Which measurement system to show amounts in.
public enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    /// As the recipe wrote them.
    case original
    /// Cups, tablespoons, ounces, pounds.
    case us
    /// Milliliters, liters, grams, kilograms.
    case metric

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: "As Written"
        case .us: "US"
        case .metric: "Metric"
        }
    }
}

/// Converts amounts between US and metric units.
public enum UnitConverter {
    /// The amount in `system`. Counts ("2 cloves"), unitless amounts and amounts
    /// already in that system come back unchanged. A parenthetical alternate in the
    /// target system ("2 cups (250 g)" to metric) is preferred over arithmetic,
    /// because the recipe author measured it.
    public static func convert(_ amount: IngredientAmount, to system: UnitSystem) -> IngredientAmount {
        guard system != .original, let unit = amount.unit, unit.kind != .count,
              let target = CookingUnit.System(system), unit.system != target else { return amount }

        if let alternate = amount.alternate, alternate.unit.system == target {
            return IngredientAmount(quantity: alternate.quantity, unit: alternate.unit, isAbbreviated: alternate.isAbbreviated)
        }
        guard let base = unit.baseValue else { return amount }
        let baseQuantity = amount.quantity.multiplied(by: base)
        let best = bestUnit(for: baseQuantity.largest, kind: unit.kind, system: target)
        guard let bestBase = best.baseValue else { return amount }
        return IngredientAmount(quantity: baseQuantity.multiplied(by: 1 / bestBase), unit: best,
                                isAbbreviated: amount.isAbbreviated || target == .metric)
    }

    /// The friendliest unit for an amount given in milliliters or grams.
    static func bestUnit(for baseValue: Double, kind: CookingUnit.Kind, system: CookingUnit.System) -> CookingUnit {
        switch (kind, system) {
        case (.volume, .metric): baseValue >= 1000 ? .liter : .milliliter
        case (.mass, .metric): baseValue >= 1000 ? .kilogram : .gram
        case (.mass, _): baseValue >= CookingUnit.pound.baseValue! ? .pound : .ounce
        default:
            if baseValue >= CookingUnit.cup.baseValue! / 4 - 0.5 {
                .cup
            } else if baseValue >= CookingUnit.tablespoon.baseValue! - 0.2 {
                .tablespoon
            } else {
                .teaspoon
            }
        }
    }
}

private extension CookingUnit.System {
    init?(_ system: UnitSystem) {
        switch system {
        case .original: return nil
        case .us: self = .us
        case .metric: self = .metric
        }
    }
}
