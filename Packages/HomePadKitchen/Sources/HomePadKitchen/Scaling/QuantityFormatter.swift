import Foundation

/// Writes amounts the way cooks read them: fractions for US and count units
/// ("1½ cups", "⅓ tsp"), rounded decimals for metric ("250 g", "1.25 l").
public enum QuantityFormatter {
    /// Fractions a cook can measure, as (value, glyph).
    private static let fractions: [(Double, String)] = [
        (0, ""), (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.375, "⅜"), (0.5, "½"),
        (0.625, "⅝"), (2.0 / 3, "⅔"), (0.75, "¾"), (0.875, "⅞"), (1, ""),
    ]

    /// "2", "1½", "2–3" for a quantity in `unit`.
    public static func string(for quantity: Quantity, unit: CookingUnit?) -> String {
        let low = number(quantity.low, unit: unit)
        guard let high = quantity.high else { return low }
        let highText = number(high, unit: unit)
        return low == highText ? low : "\(low)–\(highText)"
    }

    /// The whole amount with its unit: "1½ cups", "1 (14.5 oz) can", "2 cups (250 g)".
    public static func string(for amount: IngredientAmount) -> String {
        var parts = [string(for: amount.quantity, unit: amount.unit)]
        if let note = amount.sizeNote { parts.append(note) }
        if let unit = amount.unit {
            parts.append(unitName(unit, quantity: amount.quantity, abbreviated: amount.isAbbreviated))
        }
        if let alternate = amount.alternate {
            let alternateText = string(for: alternate.quantity, unit: alternate.unit) + " "
                + unitName(alternate.unit, quantity: alternate.quantity, abbreviated: alternate.isAbbreviated)
            parts.append("(" + alternateText + ")")
        }
        return parts.joined(separator: " ")
    }

    /// Singular or plural by the number as shown, so 1.05 cups reads "1 cup".
    private static func unitName(_ unit: CookingUnit, quantity: Quantity, abbreviated: Bool) -> String {
        unit.name(for: rounded(quantity.largest, unit: unit), abbreviated: abbreviated)
    }

    /// One number, formatted for its unit's system.
    static func number(_ value: Double, unit: CookingUnit?) -> String {
        let shown = rounded(value, unit: unit)
        if unit?.system == .metric || shown >= 20 {
            return shown.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US")))
        }
        let whole = shown.rounded(.down)
        let glyph = fractions.first { abs($0.0 - (shown - whole)) < 0.001 }?.1 ?? ""
        if whole == 0 { return glyph.isEmpty ? "0" : glyph }
        return String(Int(whole)) + glyph
    }

    /// The value as it will be shown: metric rounded to sensible steps, US and
    /// counts snapped to the nearest measurable fraction.
    static func rounded(_ value: Double, unit: CookingUnit?) -> Double {
        if let unit, unit.system == .metric {
            switch unit {
            case .kilogram, .liter: return (value * 100).rounded() / 100
            default:
                if value >= 100 { return (value / 5).rounded() * 5 }
                if value >= 10 { return value.rounded() }
                return (value * 10).rounded() / 10
            }
        }
        if value >= 20 { return value.rounded() }
        let whole = value.rounded(.down)
        let remainder = value - whole
        let nearest = fractions.min { abs($0.0 - remainder) < abs($1.0 - remainder) }?.0 ?? 0
        return whole + nearest
    }
}
