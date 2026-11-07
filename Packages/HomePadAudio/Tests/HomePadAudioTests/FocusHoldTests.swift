import Foundation
import Testing
@testable import HomePadAudio

@Suite struct FocusHoldTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func skipOnThisIPadDoesNotFlashAnotherSpeaker() {
        var hold = FocusHold(window: 1.25)
        hold.observe(.local, localIsPlaying: true, at: start)
        // Mid-skip the iPad reports paused, so the rules pick a speaker playing elsewhere.
        let midSkip = start.addingTimeInterval(0.2)
        #expect(hold.resolve(.remote("kitchen"), localIsPlaying: false, at: midSkip) == .local)
        hold.observe(.remote("kitchen"), localIsPlaying: false, at: midSkip)
        #expect(hold.resolve(.remote("kitchen"), localIsPlaying: false, at: start.addingTimeInterval(0.8)) == .local)
        // The next song starts.
        hold.observe(.local, localIsPlaying: true, at: start.addingTimeInterval(0.9))
        #expect(hold.held == .local)
        #expect(hold.lostAt == nil)
    }

    @Test func aRealChangeGoesThroughAfterTheWindow() {
        var hold = FocusHold(window: 1.25)
        hold.observe(.local, localIsPlaying: true, at: start)
        hold.observe(.remote("kitchen"), localIsPlaying: false, at: start.addingTimeInterval(1))
        #expect(hold.resolve(.remote("kitchen"), localIsPlaying: false, at: start.addingTimeInterval(2.3)) == .remote("kitchen"))
        #expect(hold.expiry(after: start.addingTimeInterval(1.5)) == start.addingTimeInterval(2.25))
        hold.observe(.remote("kitchen"), localIsPlaying: false, at: start.addingTimeInterval(2.3))
        #expect(hold.held == .remote("kitchen"))
    }

    @Test func playingOnThisIPadTakesFocusAtOnce() {
        var hold = FocusHold(window: 1.25)
        hold.observe(.remote("kitchen"), localIsPlaying: false, at: start)
        #expect(hold.resolve(.local, localIsPlaying: true, at: start.addingTimeInterval(0.1)) == .local)
        // Something merely loaded on the iPad does not take focus early.
        #expect(hold.resolve(.local, localIsPlaying: false, at: start.addingTimeInterval(0.1)) == .remote("kitchen"))
    }

    @Test func speakerSkipStaysOnThatSpeaker() {
        var hold = FocusHold(window: 1.25)
        hold.observe(.remote("living"), localIsPlaying: false, at: start)
        hold.observe(.remote("kitchen"), localIsPlaying: false, at: start.addingTimeInterval(0.3))
        #expect(hold.resolve(.remote("kitchen"), localIsPlaying: false, at: start.addingTimeInterval(0.6)) == .remote("living"))
        hold.observe(.remote("living"), localIsPlaying: false, at: start.addingTimeInterval(0.7))
        #expect(hold.held == .remote("living"))
        #expect(hold.lostAt == nil)
    }
}
