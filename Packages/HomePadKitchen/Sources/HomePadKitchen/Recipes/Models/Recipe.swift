import Foundation

/// A recipe in the kitchen library.
public struct Recipe: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String?
    /// Who published it, for example "Home Cookbook" or a site name.
    public var source: String?
    public var sourceURL: URL?
    /// Hero image on the web.
    public var imageURL: URL?
    /// A photo picked on this device, stored next to the library. Wins over `imageURL`.
    public var localImageName: String?
    public var prepTime: TimeInterval?
    public var cookTime: TimeInterval?
    public var totalTime: TimeInterval?
    /// Servings as a number, when the yield says one.
    public var servings: Int?
    /// The yield as written, for example "Makes 24 cookies".
    public var yieldText: String?
    /// Ingredient lines as written.
    public var ingredients: [String]
    public var sections: [RecipeSection]
    public var tags: [String]
    public var isPinned: Bool
    public var addedAt: Date

    public init(
        id: UUID = UUID(), title: String, summary: String? = nil, source: String? = nil, sourceURL: URL? = nil,
        imageURL: URL? = nil, localImageName: String? = nil, prepTime: TimeInterval? = nil,
        cookTime: TimeInterval? = nil, totalTime: TimeInterval? = nil, servings: Int? = nil,
        yieldText: String? = nil, ingredients: [String] = [], sections: [RecipeSection] = [],
        tags: [String] = [], isPinned: Bool = false, addedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.localImageName = localImageName
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.totalTime = totalTime
        self.servings = servings
        self.yieldText = yieldText
        self.ingredients = ingredients
        self.sections = sections
        self.tags = tags
        self.isPinned = isPinned
        self.addedAt = addedAt
    }

    /// Every step in order, across sections.
    public var steps: [RecipeStep] {
        var result: [RecipeStep] = []
        for section in sections {
            for text in section.steps {
                result.append(RecipeStep(number: result.count + 1, sectionTitle: section.title, text: text))
            }
        }
        return result
    }

    /// Total time, or prep plus cook when the total is missing.
    public var displayTime: TimeInterval? {
        if let totalTime { return totalTime }
        let sum = (prepTime ?? 0) + (cookTime ?? 0)
        return sum > 0 ? sum : nil
    }

    /// True when there is enough to cook from.
    public var isUsable: Bool {
        !title.isEmpty && !steps.isEmpty
    }
}

/// A group of steps, for recipes split into parts ("For the sauce").
public struct RecipeSection: Codable, Hashable, Sendable {
    public var title: String?
    public var steps: [String]

    public init(title: String? = nil, steps: [String]) {
        self.title = title
        self.steps = steps
    }
}

/// One step in cooking order.
public struct RecipeStep: Hashable, Sendable, Identifiable {
    public var id: Int { number }
    /// 1-based position across all sections.
    public let number: Int
    public let sectionTitle: String?
    public let text: String
}
