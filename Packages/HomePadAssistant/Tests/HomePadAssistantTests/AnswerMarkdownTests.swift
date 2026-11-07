import Foundation
import SwiftUI
import Testing
@testable import HomePadAssistant

/// Key facts in bold on screen, and never read out as asterisks.
@Suite struct AnswerMarkdownTests {
    private func boldRuns(_ text: AttributedString) -> [String] {
        text.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true ? String(text[run.range].characters) : nil
        }
    }

    @Test func boldsTheMarkedFacts() {
        let text = AnswerMarkdown.attributed("It was invented in **1842** by **Sir John Herschel**.")
        #expect(String(text.characters) == "It was invented in 1842 by Sir John Herschel.")
        #expect(boldRuns(text) == ["1842", "Sir John Herschel"])
    }

    /// SwiftUI draws Markdown bold at the font's own weight, so bold runs carry a bold font.
    @Test func boldRunsCarryTheirOwnFont() {
        let text = AnswerMarkdown.attributed("A **B** C", boldFont: .body.bold())
        #expect(text.runs.map { text[$0.range].swiftUI.font != nil } == [false, true, false])
    }

    @Test func aBoldRunStillStreamingShowsNoAsterisks() {
        let text = AnswerMarkdown.attributed("It was invented in **18")
        #expect(String(text.characters) == "It was invented in 18")
        #expect(boldRuns(text).isEmpty)
    }

    @Test func blockMarkdownStaysText() {
        let text = AnswerMarkdown.attributed("# Not a heading\n- not a list")
        #expect(String(text.characters) == "# Not a heading\n- not a list")
    }

    @Test func speechHearsNoMarks() {
        #expect(AnswerMarkdown.plain("**No**, it comes from **ancient Rome**.") == "No, it comes from ancient Rome.")
        // Sentences cut out of a bold run by the sentence chunker.
        #expect(AnswerMarkdown.plain("**Dr.") == "Dr.")
        #expect(AnswerMarkdown.plain("Smith** said so.") == "Smith said so.")
        #expect(AnswerMarkdown.plain("Plain words stay as they are.") == "Plain words stay as they are.")
    }

    @Test func onlyAnswersShownHereAskForBold() throws {
        var context = PromptContext(
            now: Date(timeIntervalSince1970: 1_792_594_800), timeZone: try #require(TimeZone(identifier: "America/Chicago")),
            locationName: nil, weather: nil, memberName: nil, aboutMember: nil, isPersonalUnlocked: false,
            personality: .concise, homeLines: [], toolNames: [], compact: false, marksKeyFacts: true
        )
        #expect(SystemPromptBuilder.build(context).contains("**1842**"))
        context.marksKeyFacts = false
        let plain = SystemPromptBuilder.build(context)
        #expect(!plain.contains("**"))
        #expect(plain.contains("plain sentences without markdown"))
    }
}
