import Foundation
import Testing
@testable import HomePadAssistant

@Suite struct VoiceLogicTests {
    @Test func wakePhraseToleratesSplitsAndMishearing() {
        #expect(WakePhraseMatcher.remainder(after: "Hey HomePad", in: "Hey HomePad, what's the weather?") == "what's the weather")
        #expect(WakePhraseMatcher.remainder(after: "Hey HomePad", in: "hey home pad turn off the lights") == "turn off the lights")
        #expect(WakePhraseMatcher.remainder(after: "Hey HomePad", in: "hay homepad") == "")
        #expect(WakePhraseMatcher.remainder(after: "Hey HomePad", in: "the home is quiet") == nil)
        #expect(WakePhraseMatcher.remainder(after: "Hey HomePad", in: "") == nil)
    }

    @Test func endOfSpeechAfterPause() {
        let start = Date(timeIntervalSince1970: 0)
        var detector = EndOfSpeechDetector(silence: 1.2, start: start)
        #expect(detector.shouldEnd(at: start.addingTimeInterval(3)) == nil)
        #expect(detector.shouldEnd(at: start.addingTimeInterval(6.5)) == .nothingHeard)
        detector.note("turn off", isFinal: false, at: start.addingTimeInterval(1))
        detector.note("turn off the lights", isFinal: false, at: start.addingTimeInterval(1.8))
        #expect(detector.shouldEnd(at: start.addingTimeInterval(2.5)) == nil)
        #expect(detector.shouldEnd(at: start.addingTimeInterval(3.1)) == .pause)
    }

    @Test func finalResultShortensTheWait() {
        let start = Date(timeIntervalSince1970: 0)
        var detector = EndOfSpeechDetector(silence: 1.2, start: start)
        detector.note("what time is it", isFinal: true, at: start.addingTimeInterval(1))
        #expect(detector.shouldEnd(at: start.addingTimeInterval(1.7)) == .pause)
        #expect(detector.shouldEnd(at: start.addingTimeInterval(40)) == .timeLimit)
    }

    @Test func sentenceChunkerSplitsOnSentenceEnds() {
        var chunker = SentenceChunker()
        #expect(chunker.append("It is 3.5 degrees outside. Bring a ") == ["It is 3.5 degrees outside."])
        // "Ok?" is too short to speak alone, so it joins the next sentence.
        #expect(chunker.append("coat! Ok? Also gloves") == ["Bring a coat!"])
        #expect(chunker.flush() == "Ok? Also gloves")
        #expect(chunker.flush() == nil)
    }

    @Test func yesNoClassifier() {
        #expect(YesNoClassifier.classify("Yes please") == true)
        #expect(YesNoClassifier.classify("go ahead") == true)
        #expect(YesNoClassifier.classify("No, don't do that") == false)
        #expect(YesNoClassifier.classify("never mind") == false)
        #expect(YesNoClassifier.classify("what's the weather") == nil)
    }

    @Test func bargeInIgnoresHomePadsOwnWords() {
        #expect(BargeInDetector.isStopCommand(heard: "the weather today is sunny stop", speaking: "The weather today is sunny."))
        #expect(!BargeInDetector.isStopCommand(heard: "the next stop is downtown", speaking: "The next stop is downtown."))
        #expect(BargeInDetector.isStopCommand(heard: "never mind", speaking: "Here is a long answer"))
    }
}
