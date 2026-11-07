import Foundation
import Testing
@testable import HomePadKitchen

@Suite struct ScalingTests {
    private func scaled(_ line: String, factor: Double = 1, system: UnitSystem = .original) -> String {
        RecipeScaler.scaledLine(line, with: AmountAdjustment(factor: factor, system: system))
    }

    // MARK: Scaling

    @Test(arguments: [
        ("2 cups flour", 1.5, "3 cups flour"),
        ("1 1/2 tsp salt", 2.0, "3 tsp salt"),
        ("3/4 cup sugar", 0.5, "⅜ cup sugar"),
        ("1 cup milk", 0.5, "½ cup milk"),
        ("1 cup milk", 1.0 / 3, "⅓ cup milk"),
        ("2 large eggs", 1.5, "3 large eggs"),
        ("1-2 cloves garlic", 2.0, "2–4 cloves garlic"),
        ("1 (14.5 oz) can tomatoes", 2.0, "2 (14.5 oz) cans tomatoes"),
        ("200g butter", 0.5, "100 g butter"),
        ("2 cups (250 g) flour", 2.0, "4 cups (500 g) flour"),
        ("1 tablespoon oil", 3.0, "3 tablespoons oil"),
        ("24 cookies", 2.0, "48 cookies"),
        ("Salt to taste", 2.0, "Salt to taste"),
    ])
    func scalesAmounts(_ line: String, _ factor: Double, _ expected: String) {
        #expect(scaled(line, factor: factor) == expected)
    }

    @Test func identityKeepsAuthorWording() {
        #expect(scaled("1 1/2 cups (190g) flour, sifted") == "1 1/2 cups (190g) flour, sifted")
        let display = RecipeScaler.display(IngredientParser.parse("2 tbsp. butter"), with: AmountAdjustment())
        #expect(display.amount == "2 tbsp.")
        #expect(display.name == "butter")
    }

    @Test func servingsFactor() {
        #expect(AmountAdjustment.factor(from: 4, to: 6) == 1.5)
        #expect(AmountAdjustment.factor(from: 4, to: 2) == 0.5)
        #expect(AmountAdjustment.factor(from: nil, to: 6) == 1)
        #expect(AmountAdjustment.factor(from: 0, to: 6) == 1)
    }

    // MARK: Unit conversion

    @Test(arguments: [
        ("1 cup milk", "235 ml milk"),
        ("4 cups vegetable broth", "945 ml vegetable broth"),
        ("5 cups stock", "1.18 l stock"),
        ("2 tablespoons olive oil", "30 ml olive oil"),
        ("1 teaspoon salt", "4.9 ml salt"),
        ("1 pound ground beef", "455 g ground beef"),
        ("8 oz cream cheese", "225 g cream cheese"),
        ("3 lb pork shoulder", "1.36 kg pork shoulder"),
        ("2 cups (250 g) flour", "250 g flour"),
        ("2 cloves garlic", "2 cloves garlic"),
        ("3 eggs", "3 eggs"),
        ("200 g butter", "200 g butter"),
    ])
    func convertsToMetric(_ line: String, _ expected: String) {
        #expect(scaled(line, system: .metric) == expected)
    }

    @Test(arguments: [
        ("250 ml milk", "1 cup milk"),
        ("500 ml stock", "2⅛ cups stock"),
        ("15 ml oil", "1 tbsp oil"),
        ("5 ml vanilla", "1 tsp vanilla"),
        ("45 ml lemon juice", "3 tbsp lemon juice"),
        ("200g butter", "7 oz butter"),
        ("1 kg potatoes", "2¼ lb potatoes"),
        ("1 cup sugar", "1 cup sugar"),
    ])
    func convertsToUS(_ line: String, _ expected: String) {
        #expect(scaled(line, system: .us) == expected)
    }

    @Test func scalesThenConverts() {
        #expect(scaled("1 cup milk", factor: 2, system: .metric) == "475 ml milk")
        #expect(scaled("100 g sugar", factor: 1.5, system: .us) == "5¼ oz sugar")
    }

    // MARK: Formatting

    @Test(arguments: [
        (0.125, "⅛"), (0.25, "¼"), (0.33, "⅓"), (0.5, "½"), (0.66, "⅔"), (0.75, "¾"), (1.0, "1"),
        (1.5, "1½"), (2.97, "3"), (2.02, "2"), (21.4, "21"), (0.04, "0"),
    ])
    func usFractions(_ value: Double, _ expected: String) {
        #expect(QuantityFormatter.number(value, unit: .cup) == expected)
    }

    @Test(arguments: [
        (CookingUnit.gram, 453.592, "455"), (.gram, 28.35, "28"), (.gram, 4.93, "4.9"),
        (.milliliter, 236.588, "235"), (.kilogram, 1.3608, "1.36"), (.liter, 2.0, "2"),
    ])
    func metricRounding(_ unit: CookingUnit, _ value: Double, _ expected: String) {
        #expect(QuantityFormatter.number(value, unit: unit) == expected)
    }

    // MARK: Step text

    @Test func stepSegmentsHighlightAmountsAndTimes() {
        let segments = StepTextAnalyzer.segments(for: "Whisk 1 cup milk, then cook 3 to 5 minutes.")
        #expect(segments.map(\.text).joined() == "Whisk 1 cup milk, then cook 3 to 5 minutes.")
        #expect(segments.filter { $0.kind == .amount }.map(\.text) == ["1 cup"])
        let durations = segments.compactMap { segment -> DetectedDuration? in
            if case .duration(let duration) = segment.kind { return duration }
            return nil
        }
        #expect(durations.map(\.text) == ["3 to 5 minutes"])
    }

    @Test func stepAmountsScaleAndConvert() {
        let adjustment = AmountAdjustment(factor: 2, system: .metric)
        let text = StepTextAnalyzer.plainText(for: "Add 1 cup broth and simmer 10 minutes.", adjustment: adjustment)
        #expect(text == "Add 475 ml broth and simmer 10 minutes.")
    }

    // MARK: Session

    @MainActor
    @Test func sessionScalesChecklistAndMissingItems() {
        let recipe = Recipe(title: "Soup", servings: 4, ingredients: ["2 cups broth", "1 onion", "Salt"],
                            sections: [RecipeSection(steps: ["Chop.", "Simmer 20 minutes."])])
        let session = RecipeSession(recipe: recipe)
        session.servings = 8
        #expect(session.displayIngredients.map(\.text) == ["4 cups broth", "2 onion", "Salt"])
        session.toggleIngredient(1)
        #expect(session.missingIngredients == ["4 cups broth", "Salt"])
        #expect(session.next())
        #expect(!session.next())
        #expect(session.spokenStep() == "Step 2 of 2. Simmer 20 minutes.")
        #expect(session.previous())
        #expect(!session.previous())
    }

    @MainActor
    @Test func defaultServingsOverrideRecipe() {
        let recipe = Recipe(title: "Soup", servings: 4, ingredients: ["1 cup rice"], sections: [RecipeSection(steps: ["Cook."])])
        #expect(RecipeSession(recipe: recipe, defaultServings: 2).displayIngredients.first?.text == "½ cup rice")
        #expect(RecipeSession(recipe: recipe, defaultServings: 0).servings == 4)
    }
}
