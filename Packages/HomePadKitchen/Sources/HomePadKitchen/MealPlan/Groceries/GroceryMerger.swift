import Foundation

/// One line of a shopping list made from planned meals.
public struct GroceryItem: Identifiable, Hashable, Sendable {
    public var id: String { key }
    /// What lines are matched by (`GroceryName.key(for:)`), such as "yellow onion".
    public let key: String
    /// The name as the recipes write it, plural for a count above one.
    public let name: String
    /// Everything the meals need, added up: "1½ cups", or "2 cups and 200 g"
    /// when volume and weight cannot be added. Nil when no recipe gave an amount.
    public let amount: String?
    /// The recipes that need it, in plan order.
    public let recipes: [String]

    /// The reminder's title: "3 yellow onions", "⅜ cup olive oil", "Salt".
    public var text: String {
        guard let amount else { return name.prefix(1).uppercased() + name.dropFirst() }
        return "\(amount) \(name)"
    }
}

/// A planned recipe and how many it is cooked for. Nil servings cooks it as written.
public struct MealServing: Sendable {
    public let recipe: Recipe
    public let servings: Int?

    public init(recipe: Recipe, servings: Int?) {
        self.recipe = recipe
        self.servings = servings
    }
}

/// Adds up the ingredients of several planned recipes into one shopping list.
///
/// Each line is scaled to the meal's servings first (`RecipeScaler`). Lines
/// whose names match (`GroceryName`) become one item. Amounts add up when the
/// parsing and scaling code can convert them: volumes with volumes and weights
/// with weights through `CookingUnit.baseValue`, counts of the same unit, and
/// bare counts. Volume and weight of the same thing cannot be added without
/// its density, so they are listed side by side.
public enum GroceryMerger {
    /// - Parameter system: The household's units setting. As written keeps
    ///   each recipe's units where they agree and picks the friendliest unit
    ///   of the first recipe's system where they do not.
    public static func merge(_ meals: [MealServing], system: UnitSystem = .original) -> [GroceryItem] {
        var order: [String] = []
        var groups: [String: Group] = [:]
        for meal in meals {
            let factor = meal.servings.map { AmountAdjustment.factor(from: meal.recipe.servings, to: $0) } ?? 1
            let adjustment = AmountAdjustment(factor: factor, system: system)
            for line in meal.recipe.ingredients {
                guard let entry = entry(for: line, adjustment: adjustment) else { continue }
                if groups[entry.key] == nil {
                    order.append(entry.key)
                    groups[entry.key] = Group()
                }
                groups[entry.key]?.add(entry, recipe: meal.recipe.title)
            }
        }
        return order.compactMap { key in groups[key]?.item(key: key, system: system) }
    }

    /// The key of a line already on a list ("Eggs", "3 yellow onions"), to
    /// tell whether a merged item is there. Nil for a line with no name.
    public static func key(forListItem title: String) -> String? {
        entry(for: title, adjustment: AmountAdjustment())?.key
    }

    // MARK: Lines

    private struct Entry {
        var key: String
        var name: String
        var amount: IngredientAmount?
    }

    private static func entry(for line: String, adjustment: AmountAdjustment) -> Entry? {
        let parsed = IngredientParser.parse(line)
        var amount = parsed.amount.map { RecipeScaler.adjust($0, with: adjustment) }
        guard var cleaned = GroceryName.clean(parsed.name, unit: amount?.unit) else { return nil }
        // "3 garlic cloves" counts cloves, like "3 cloves garlic".
        if amount != nil, amount?.unit == nil, let split = GroceryName.trailingCountUnit(in: cleaned.name) {
            amount?.unit = split.unit
            cleaned = GroceryName.Cleaned(name: split.name, key: GroceryName.key(for: split.name))
        }
        return Entry(key: cleaned.key, name: cleaned.name, amount: amount)
    }

    // MARK: Adding up

    /// One ingredient's amounts, as many as cannot be added to each other.
    private struct Group {
        var names: [String] = []
        var parts: [Part] = []
        var recipes: [String] = []

        mutating func add(_ entry: Entry, recipe: String) {
            if !names.contains(entry.name) { names.append(entry.name) }
            if !recipes.contains(recipe) { recipes.append(recipe) }
            guard let amount = entry.amount else { return }
            if let index = parts.firstIndex(where: { $0.canAdd(amount) }) {
                parts[index].add(amount)
            } else {
                parts.append(Part(amount))
            }
        }

        func item(key: String, system: UnitSystem) -> GroceryItem {
            let amounts = parts.map { $0.amount(preferring: system) }
            let text = amounts.isEmpty ? nil : amounts.map(QuantityFormatter.string(for:)).joined(separator: " and ")
            return GroceryItem(key: key, name: name(for: amounts), amount: text, recipes: recipes)
        }

        /// A count above one reads in the plural ("3 onions"), one in the
        /// singular, and anything measured as the first recipe wrote it.
        private func name(for amounts: [IngredientAmount]) -> String {
            let first = names.first ?? ""
            guard amounts.count == 1, amounts[0].unit == nil else { return first }
            let isPlural = { (name: String) in GroceryName.key(for: name) != name.lowercased() }
            if amounts[0].quantity.largest > 1.0001 {
                return names.first(where: isPlural) ?? GroceryName.plural(first)
            }
            return names.first(where: { !isPlural($0) }) ?? first
        }
    }

    /// Amounts that add up: a bare count, a count of one unit and package
    /// size, or a volume or a weight kept in milliliters or grams.
    private struct Part {
        var unit: CookingUnit?
        var sizeNote: String?
        var isAbbreviated: Bool
        /// In `unit`, or in milliliters or grams for a volume or a weight.
        var quantity: Quantity
        /// Every unit a volume or weight was written in, in order.
        var writtenUnits: [CookingUnit] = []

        init(_ amount: IngredientAmount) {
            unit = amount.unit
            sizeNote = amount.sizeNote
            isAbbreviated = amount.isAbbreviated
            quantity = Self.base(amount)
            if let unit = amount.unit, unit.kind != .count { writtenUnits = [unit] }
        }

        func canAdd(_ amount: IngredientAmount) -> Bool {
            switch (unit, amount.unit) {
            case (nil, nil): true
            case let (mine?, theirs?) where mine.kind == .count: mine == theirs && sizeNote == amount.sizeNote
            case let (mine?, theirs?): mine.kind == theirs.kind
            default: false
            }
        }

        mutating func add(_ amount: IngredientAmount) {
            quantity = Self.sum(quantity, Self.base(amount))
            if let unit = amount.unit, unit.kind != .count { writtenUnits.append(unit) }
        }

        /// The total in the unit it was written in when every recipe agreed,
        /// otherwise in the friendliest unit of one system.
        func amount(preferring system: UnitSystem) -> IngredientAmount {
            guard let unit, unit.kind != .count, let first = writtenUnits.first else {
                // Nobody buys half an onion or half a can.
                let counted = Self.isBoughtWhole(unit) ? Self.wholeUp(quantity) : quantity
                return IngredientAmount(quantity: counted, unit: unit, isAbbreviated: isAbbreviated, sizeNote: sizeNote)
            }
            let shown: CookingUnit
            if writtenUnits.allSatisfy({ $0 == first }) {
                shown = first
            } else {
                let systems = Set(writtenUnits.map(\.system))
                let target = systems.count == 1 ? first.system : (Self.system(system) ?? first.system)
                shown = UnitConverter.bestUnit(for: quantity.largest, kind: unit.kind, system: target)
            }
            let scale = 1 / (shown.baseValue ?? 1)
            return IngredientAmount(quantity: quantity.multiplied(by: scale), unit: shown,
                                    isAbbreviated: isAbbreviated || shown.system == .metric)
        }

        private static func base(_ amount: IngredientAmount) -> Quantity {
            guard let unit = amount.unit, unit.kind != .count, let base = unit.baseValue else { return amount.quantity }
            return amount.quantity.multiplied(by: base)
        }

        /// Bare counts and the units things are sold in. A pinch, a dash, a
        /// sprig or a handful is a measure of something bought another way.
        private static func isBoughtWhole(_ unit: CookingUnit?) -> Bool {
            guard let unit else { return true }
            return ![.pinch, .dash, .sprig, .handful].contains(unit)
        }

        /// Rounds each end up to a whole number. Scaling leaves values such as
        /// 3.0000001, which must stay 3.
        private static func wholeUp(_ quantity: Quantity) -> Quantity {
            let up = { (value: Double) in max(1, (value - 0.001).rounded(.up)) }
            return Quantity(up(quantity.low), high: quantity.high.map(up))
        }

        /// Ranges add end to end: "2 to 3" and "1" make "3 to 4".
        private static func sum(_ a: Quantity, _ b: Quantity) -> Quantity {
            let high: Double? = (a.high != nil || b.high != nil) ? a.largest + b.largest : nil
            return Quantity(a.low + b.low, high: high)
        }

        private static func system(_ system: UnitSystem) -> CookingUnit.System? {
            switch system {
            case .original: nil
            case .us: .us
            case .metric: .metric
            }
        }
    }
}
