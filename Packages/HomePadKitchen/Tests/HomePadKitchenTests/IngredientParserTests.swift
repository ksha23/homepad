import Foundation
import Testing
@testable import HomePadKitchen

@Suite struct IngredientParserTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let line: String
        let low: Double?
        var high: Double?
        let unit: CookingUnit?
        let name: String
        var amountText: String?
        var testDescription: String { line }
    }

    static let cases: [Case] = [
        Case(line: "2 cups all-purpose flour", low: 2, unit: .cup, name: "all-purpose flour", amountText: "2 cups"),
        Case(line: "1 1/2 tsp kosher salt", low: 1.5, unit: .teaspoon, name: "kosher salt", amountText: "1 1/2 tsp"),
        Case(line: "½ cup sugar", low: 0.5, unit: .cup, name: "sugar"),
        Case(line: "1½ cups milk", low: 1.5, unit: .cup, name: "milk"),
        Case(line: "1 ½ pounds ground beef", low: 1.5, unit: .pound, name: "ground beef"),
        Case(line: "3/4 cup granulated sugar", low: 0.75, unit: .cup, name: "granulated sugar"),
        Case(line: "1-2 cloves garlic", low: 1, high: 2, unit: .clove, name: "garlic"),
        Case(line: "2 to 3 tablespoons olive oil", low: 2, high: 3, unit: .tablespoon, name: "olive oil"),
        Case(line: "3 large eggs", low: 3, unit: nil, name: "large eggs", amountText: "3"),
        Case(line: "200g butter", low: 200, unit: .gram, name: "butter", amountText: "200g"),
        Case(line: "250 ml whole milk", low: 250, unit: .milliliter, name: "whole milk"),
        Case(line: "1 lb. ground pork", low: 1, unit: .pound, name: "ground pork", amountText: "1 lb."),
        Case(line: "2 tbsp. butter", low: 2, unit: .tablespoon, name: "butter"),
        Case(line: "1 T honey", low: 1, unit: .tablespoon, name: "honey"),
        Case(line: "1 t vanilla", low: 1, unit: .teaspoon, name: "vanilla"),
        Case(line: "1 (14.5 oz) can diced tomatoes", low: 1, unit: .can, name: "diced tomatoes", amountText: "1 (14.5 oz) can"),
        Case(line: "2 cups (250 g) flour", low: 2, unit: .cup, name: "flour", amountText: "2 cups (250 g)"),
        Case(line: "A pinch of salt", low: 1, unit: .pinch, name: "salt"),
        Case(line: "One 12-ounce bag chocolate chips", low: 1, unit: nil, name: "12-ounce bag chocolate chips"),
        Case(line: "1 and 1/2 cups water", low: 1.5, unit: .cup, name: "water"),
        Case(line: "2 fl oz cream", low: 2, unit: .fluidOunce, name: "cream"),
        Case(line: "• 1/2 teaspoon nutmeg", low: 0.5, unit: .teaspoon, name: "nutmeg"),
        Case(line: "0.5 kg potatoes", low: 0.5, unit: .kilogram, name: "potatoes"),
        Case(line: "4 green onions, sliced", low: 4, unit: nil, name: "green onions, sliced"),
        Case(line: "2 large onions", low: 2, unit: nil, name: "large onions"),
        Case(line: "Salt and pepper, to taste", low: nil, unit: nil, name: "Salt and pepper, to taste"),
        Case(line: "tender greens", low: nil, unit: nil, name: "tender greens"),
        Case(line: "Juice of 1 lemon", low: nil, unit: nil, name: "Juice of 1 lemon"),
    ]

    @Test(arguments: cases)
    func parsesLine(_ testCase: Case) {
        let parsed = IngredientParser.parse(testCase.line)
        #expect(parsed.amount?.quantity.low == testCase.low)
        #expect(parsed.amount?.quantity.high == testCase.high)
        #expect(parsed.amount?.unit == testCase.unit)
        #expect(parsed.name == testCase.name)
        if let amountText = testCase.amountText {
            #expect(parsed.writtenAmount == amountText)
        }
    }

    @Test func keepsPackageSizeAndAlternate() throws {
        let can = try #require(IngredientParser.parse("1 (14.5 oz) can diced tomatoes").amount)
        #expect(can.sizeNote == "(14.5 oz)")
        let flour = try #require(IngredientParser.parse("2 cups (250 g) flour").amount)
        #expect(flour.alternate?.unit == .gram)
        #expect(flour.alternate?.quantity.low == 250)
    }

    @Test func abbreviationIsRemembered() {
        #expect(IngredientParser.parse("2 tbsp butter").amount?.isAbbreviated == true)
        #expect(IngredientParser.parse("2 tablespoons butter").amount?.isAbbreviated == false)
        #expect(IngredientParser.parse("1 cup rice").amount?.isAbbreviated == false)
        #expect(IngredientParser.parse("200 g rice").amount?.isAbbreviated == true)
    }

    @Test(arguments: [("1 1/2", 1.5), ("1½", 1.5), ("⅔", 2.0 / 3), ("3/4", 0.75), ("2.25", 2.25),
                      ("one", 1), ("a", 1), ("half a", 0.5), ("a couple of", 2), ("1 and 1/2", 1.5), ("1⁄4", 0.25)])
    func readsNumbers(_ text: String, _ value: Double) throws {
        let parsed = try #require(NumberGrammar.value(of: text))
        #expect(abs(parsed - value) < 0.0001)
    }

    @Test func findsMeasuredAmountsInStepText() {
        let found = QuantityParser.findMeasured(in: "Whisk 2 cups milk with 1/2 teaspoon salt and 200g sugar at 350 degrees in a 9-inch pan.")
        #expect(found.map { $0.amount.unit } == [.cup, .teaspoon, .gram])
        #expect(found.map { $0.amount.quantity.low } == [2, 0.5, 200])
    }

    @Test func stepTextDoesNotHighlightBareNumbers() {
        #expect(QuantityParser.findMeasured(in: "Step 2: preheat to 350 and use 3 eggs.").isEmpty)
    }
}
