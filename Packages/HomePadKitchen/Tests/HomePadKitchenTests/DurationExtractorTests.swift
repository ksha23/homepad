import Foundation
import Testing
@testable import HomePadKitchen

@Suite struct DurationExtractorTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let text: String
        let match: String
        let lower: TimeInterval
        let upper: TimeInterval
        var testDescription: String { text }
    }

    static let singleDurations: [Case] = [
        Case(text: "Simmer for 5 minutes.", match: "5 minutes", lower: 300, upper: 300),
        Case(text: "Cook until soft, 3 to 5 minutes.", match: "3 to 5 minutes", lower: 180, upper: 300),
        Case(text: "Bake 25–30 min, until golden.", match: "25–30 min", lower: 1500, upper: 1800),
        Case(text: "Roast 5-7 mins per side", match: "5-7 mins", lower: 300, upper: 420),
        Case(text: "Braise for 1 hour 20 min.", match: "1 hour 20 min", lower: 4800, upper: 4800),
        Case(text: "Chill 1 hr and 15 minutes before rolling.", match: "1 hr and 15 minutes", lower: 4500, upper: 4500),
        Case(text: "Bake 1½ hours.", match: "1½ hours", lower: 5400, upper: 5400),
        Case(text: "Bake 1 1/2 hours.", match: "1 1/2 hours", lower: 5400, upper: 5400),
        Case(text: "Let it rise for an hour and a half.", match: "an hour and a half", lower: 5400, upper: 5400),
        Case(text: "Rest half an hour.", match: "half an hour", lower: 1800, upper: 1800),
        Case(text: "Soak for about 5 seconds on each side.", match: "5 seconds", lower: 5, upper: 5),
        Case(text: "Cook 45 minutes to 1 hour.", match: "45 minutes to 1 hour", lower: 2700, upper: 3600),
        Case(text: "Whisk for a minute.", match: "a minute", lower: 60, upper: 60),
        Case(text: "Simmer ten minutes.", match: "ten minutes", lower: 600, upper: 600),
        Case(text: "Bake 10 more minutes.", match: "10 more minutes", lower: 600, upper: 600),
        Case(text: "Give it a 10-minute rest.", match: "10-minute", lower: 600, upper: 600),
        Case(text: "Sous vide 2 to 3 hrs.", match: "2 to 3 hrs", lower: 7200, upper: 10800),
        Case(text: "Pressure cook 1h 30m.", match: "1h 30m", lower: 5400, upper: 5400),
        Case(text: "Steam 1 to 1 1/2 hours.", match: "1 to 1 1/2 hours", lower: 3600, upper: 5400),
        Case(text: "Fry 1 minute and 30 seconds.", match: "1 minute and 30 seconds", lower: 90, upper: 90),
        Case(text: "Microwave for 2.5 minutes.", match: "2.5 minutes", lower: 150, upper: 150),
    ]

    @Test(arguments: singleDurations)
    func findsDuration(_ testCase: Case) throws {
        let found = DurationExtractor.extract(from: testCase.text)
        try #require(found.count == 1)
        #expect(found[0].text == testCase.match)
        #expect(found[0].lowerBound == testCase.lower)
        #expect(found[0].upperBound == testCase.upper)
        #expect(String(testCase.text[found[0].range]) == testCase.match)
    }

    @Test(arguments: [
        "Preheat the oven to 350°F.",
        "Use a 9x13-inch pan and 2 cups of flour.",
        "Add the second egg.",
        "Repeat a second time.",
        "Cook for several minutes.",
        "Place in a pan and mix.",
        "Serve in the 1970s style.",
    ])
    func ignoresNonDurations(_ text: String) {
        #expect(DurationExtractor.extract(from: text).isEmpty)
    }

    @Test func findsSeveralDurationsInOneStep() {
        let found = DurationExtractor.extract(from: "Sear 2 minutes per side, then roast 20 to 25 minutes and rest 10 minutes.")
        #expect(found.map(\.text) == ["2 minutes", "20 to 25 minutes", "10 minutes"])
        #expect(found.map(\.lowerBound) == [120, 1200, 600])
        #expect(found[1].isRange)
        #expect(!found[0].isRange)
    }

    @Test(arguments: [
        ("PT15M", 900.0), ("PT1H30M", 5400), ("P0DT0H25M", 1500), ("PT0.5H", 1800), ("pt90m", 5400),
        ("P0Y0M0DT0H35M0.000S", 2100), ("PT1H0M10S", 3610), ("P1D", 86400), ("PT 20 M", 1200),
    ])
    func parsesISO8601(_ text: String, _ seconds: Double) {
        #expect(ISO8601Duration.seconds(from: text) == seconds)
    }

    @Test(arguments: ["", "P", "PT", "15 minutes", "1:30", "PTXM"])
    func rejectsNonISO8601(_ text: String) {
        #expect(ISO8601Duration.seconds(from: text) == nil)
    }

    @Test func recipeTimeFallsBackToText() {
        #expect(ISO8601Duration.recipeTime(from: "PT0S") == nil)
        #expect(ISO8601Duration.recipeTime(from: "20 mins") == 1200)
        #expect(ISO8601Duration.recipeTime(from: "1 hour 10 minutes") == 4200)
        #expect(ISO8601Duration.recipeTime(from: "PT25M") == 1500)
    }
}
