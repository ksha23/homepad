import Foundation
import Observation

/// One open recipe: the card, its ingredient checklist and cooking mode share it,
/// so servings, units and ticked ingredients carry from the card into cooking.
@MainActor
@Observable
public final class RecipeSession {
    public let recipe: Recipe
    public let steps: [RecipeStep]
    public let ingredients: [ParsedIngredient]
    public private(set) var stepIndex = 0
    /// Servings to cook for. Amounts scale from the recipe's own servings.
    public var servings: Int
    public var unitSystem: UnitSystem
    /// Indexes into `ingredients` that are ready on the counter.
    public private(set) var checkedIngredients: Set<Int> = []

    /// - Parameter defaultServings: Starting servings, or 0 for the recipe's own.
    public init(recipe: Recipe, defaultServings: Int = 0, unitSystem: UnitSystem = .original) {
        self.recipe = recipe
        self.steps = recipe.steps
        self.ingredients = recipe.ingredients.map(IngredientParser.parse)
        self.servings = defaultServings > 0 ? defaultServings : (recipe.servings ?? 4)
        self.unitSystem = unitSystem
    }

    // MARK: Steps

    public var currentStep: RecipeStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    public var isFirstStep: Bool { stepIndex == 0 }
    public var isLastStep: Bool { stepIndex >= steps.count - 1 }

    /// Moves to the next step. False on the last step.
    @discardableResult
    public func next() -> Bool {
        guard !isLastStep else { return false }
        stepIndex += 1
        return true
    }

    /// Moves to the previous step. False on the first step.
    @discardableResult
    public func previous() -> Bool {
        guard !isFirstStep else { return false }
        stepIndex -= 1
        return true
    }

    public func go(to index: Int) {
        stepIndex = min(max(0, index), max(0, steps.count - 1))
    }

    // MARK: Amounts

    public var adjustment: AmountAdjustment {
        AmountAdjustment(factor: AmountAdjustment.factor(from: recipe.servings, to: servings), system: unitSystem)
    }

    /// True when the recipe states servings, so scaling is meaningful.
    public var canScale: Bool { (recipe.servings ?? 0) > 0 }

    public var displayIngredients: [DisplayIngredient] {
        ingredients.map { RecipeScaler.display($0, with: adjustment) }
    }

    /// A step split into plain text, orange amounts and timer chips.
    public func segments(for step: RecipeStep) -> [StepSegment] {
        StepTextAnalyzer.segments(for: step.text, adjustment: adjustment)
    }

    /// "Step 3 of 7. Whisk the eggs..." for reading aloud.
    public func spokenStep() -> String {
        guard let step = currentStep else { return "This recipe has no steps." }
        let text = StepTextAnalyzer.plainText(for: step.text, adjustment: adjustment)
        return "Step \(step.number) of \(steps.count). \(text)"
    }

    // MARK: Checklist

    public func toggleIngredient(_ index: Int) {
        if checkedIngredients.contains(index) {
            checkedIngredients.remove(index)
        } else {
            checkedIngredients.insert(index)
        }
    }

    /// Ingredients not ticked off, as full lines for the grocery list.
    public var missingIngredients: [String] {
        displayIngredients.enumerated()
            .filter { !checkedIngredients.contains($0.offset) }
            .map(\.element.text)
    }

    /// A timer label such as "Step 2 · Butternut Squash Soup". Steps with several
    /// times name the time too, so each chip gets its own timer.
    public func timerLabel(for step: RecipeStep, duration: DetectedDuration) -> String {
        let several = DurationExtractor.extract(from: step.text).count > 1
        let stepName = several ? "Step \(step.number), \(duration.text)" : "Step \(step.number)"
        return "\(stepName) · \(recipe.title)"
    }
}
