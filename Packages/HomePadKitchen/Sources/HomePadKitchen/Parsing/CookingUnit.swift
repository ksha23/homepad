import Foundation

/// A unit recipes measure ingredients in. Volume and mass units convert between
/// US and metric. Count units ("clove", "can") only scale.
public enum CookingUnit: String, Codable, CaseIterable, Sendable {
    // US volume
    case teaspoon, tablespoon, fluidOunce, cup, pint, quart, gallon
    // Metric volume
    case milliliter, deciliter, liter
    // Mass
    case ounce, pound, gram, kilogram, milligram
    // Counts
    case clove, can, pinch, dash, stick, slice, piece, package, bunch, sprig, head, stalk, handful, jar, bottle

    public enum Kind: Sendable { case volume, mass, count }

    public enum System: Sendable { case us, metric, neutral }

    public var kind: Kind {
        switch self {
        case .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart, .gallon, .milliliter, .deciliter, .liter: .volume
        case .ounce, .pound, .gram, .kilogram, .milligram: .mass
        default: .count
        }
    }

    public var system: System {
        switch self {
        case .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart, .gallon, .ounce, .pound: .us
        case .milliliter, .deciliter, .liter, .gram, .kilogram, .milligram: .metric
        default: .neutral
        }
    }

    /// Size in the base unit of its kind (milliliters or grams). Nil for counts.
    public var baseValue: Double? {
        switch self {
        case .teaspoon: 4.92892
        case .tablespoon: 14.7868
        case .fluidOunce: 29.5735
        case .cup: 236.588
        case .pint: 473.176
        case .quart: 946.353
        case .gallon: 3785.41
        case .milliliter: 1
        case .deciliter: 100
        case .liter: 1000
        case .ounce: 28.3495
        case .pound: 453.592
        case .gram: 1
        case .kilogram: 1000
        case .milligram: 0.001
        default: nil
        }
    }

    /// Ways the unit is written, matched case-insensitively unless listed in `caseSensitiveAliases`.
    var aliases: [String] {
        switch self {
        case .teaspoon: ["teaspoons", "teaspoon", "tsps", "tsp.", "tsp", "tspn"]
        case .tablespoon: ["tablespoons", "tablespoon", "tbsps", "tbsp.", "tbsp", "tbls", "tbl.", "tbl", "tbs.", "tbs"]
        case .fluidOunce: ["fluid ounces", "fluid ounce", "fl. oz.", "fl. oz", "fl oz.", "fl oz", "fl.oz."]
        case .cup: ["cups", "cup", "c.", "c"]
        case .pint: ["pints", "pint", "pts", "pt."]
        case .quart: ["quarts", "quart", "qts", "qt.", "qt"]
        case .gallon: ["gallons", "gallon", "gal."]
        case .milliliter: ["milliliters", "milliliter", "millilitres", "millilitre", "ml.", "ml", "cc"]
        case .deciliter: ["deciliters", "deciliter", "decilitres", "decilitre", "dl"]
        case .liter: ["liters", "liter", "litres", "litre", "l"]
        case .ounce: ["ounces", "ounce", "oz.", "oz"]
        case .pound: ["pounds", "pound", "lbs.", "lbs", "lb.", "lb"]
        case .gram: ["grams", "gram", "grammes", "gramme", "gr.", "g"]
        case .kilogram: ["kilograms", "kilogram", "kilos", "kilo", "kgs", "kg"]
        case .milligram: ["milligrams", "milligram", "mg"]
        case .clove: ["cloves", "clove"]
        case .can: ["cans", "can"]
        case .pinch: ["pinches", "pinch"]
        case .dash: ["dashes", "dash"]
        case .stick: ["sticks", "stick"]
        case .slice: ["slices", "slice"]
        case .piece: ["pieces", "piece"]
        case .package: ["packages", "package", "pkgs", "pkg.", "pkg", "packets", "packet"]
        case .bunch: ["bunches", "bunch"]
        case .sprig: ["sprigs", "sprig"]
        case .head: ["heads", "head"]
        case .stalk: ["stalks", "stalk"]
        case .handful: ["handfuls", "handful"]
        case .jar: ["jars", "jar"]
        case .bottle: ["bottles", "bottle"]
        }
    }

    /// "T" means tablespoon and "t" teaspoon, so these two are matched case-sensitively.
    static let caseSensitiveAliases: [(String, CookingUnit)] = [("T", .tablespoon), ("t", .teaspoon)]

    /// Every alias with its unit, longest first so "fl oz" wins over "oz".
    static let aliasTable: [(String, CookingUnit)] = {
        allCases.flatMap { unit in unit.aliases.map { ($0, unit) } }
            .sorted { $0.0.count > $1.0.count }
    }()

    /// The display name for a value: "cup" or "cups", "tbsp" when abbreviated.
    public func name(for value: Double, abbreviated: Bool) -> String {
        let plural = value > 1.0001 || value == 0
        if abbreviated, let short = abbreviation { return short }
        switch self {
        case .fluidOunce: return plural ? "fluid ounces" : "fluid ounce"
        case .pinch: return plural ? "pinches" : "pinch"
        case .dash: return plural ? "dashes" : "dash"
        case .bunch: return plural ? "bunches" : "bunch"
        default: return plural ? rawValue + "s" : rawValue
        }
    }

    private var abbreviation: String? {
        switch self {
        case .teaspoon: "tsp"
        case .tablespoon: "tbsp"
        case .fluidOunce: "fl oz"
        case .pint: "pt"
        case .quart: "qt"
        case .gallon: "gal"
        case .milliliter: "ml"
        case .deciliter: "dl"
        case .liter: "l"
        case .ounce: "oz"
        case .pound: "lb"
        case .gram: "g"
        case .kilogram: "kg"
        case .milligram: "mg"
        default: nil
        }
    }

    /// Reads a unit at the very start of `text`, which must end at a word
    /// boundary ("g flour" is grams, "green" is not). Returns the unit and its length.
    static func match(atStartOf text: Substring) -> (unit: CookingUnit, length: Int)? {
        for (alias, unit) in caseSensitiveAliases where text.hasPrefix(alias) {
            if endsAtWordBoundary(text, after: alias.count) { return (unit, alias.count) }
        }
        let lowered = text.lowercased()
        for (alias, unit) in aliasTable where lowered.hasPrefix(alias) {
            if endsAtWordBoundary(text, after: alias.count) { return (unit, alias.count) }
        }
        return nil
    }

    private static func endsAtWordBoundary(_ text: Substring, after length: Int) -> Bool {
        guard let next = text.dropFirst(length).first else { return true }
        return !next.isLetter
    }
}
