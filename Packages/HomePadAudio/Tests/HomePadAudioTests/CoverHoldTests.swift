import Foundation
import Testing
@testable import HomePadAudio

/// The cover never shows another song's artwork for long, and never a stand-in.
@Suite struct CoverHoldTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func realCoverShowsAtOnce() {
        var hold = CoverHold<String>(window: 1.0)
        #expect(hold.update(entryID: "a", real: "A", isLoading: false, at: start) == "A")
        #expect(hold.update(entryID: "b", real: "B", isLoading: false, at: start.addingTimeInterval(5)) == "B")
    }

    @Test func previousCoverStaysBrieflyWhileTheNextLoads() {
        var hold = CoverHold<String>(window: 1.0)
        _ = hold.update(entryID: "a", real: "A", isLoading: false, at: start)
        #expect(hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(10)) == "A")
        #expect(hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(10.6)) == "A")
        #expect(hold.expiry(after: start.addingTimeInterval(10.6)) == start.addingTimeInterval(11))
        #expect(hold.update(entryID: "b", real: "B", isLoading: false, at: start.addingTimeInterval(10.8)) == "B",
                "the real cover replaces it as soon as it arrives")
    }

    @Test func anotherSongsCoverGivesWayAfterTheWindow() {
        var hold = CoverHold<String>(window: 1.0)
        _ = hold.update(entryID: "a", real: "A", isLoading: false, at: start)
        _ = hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(10))
        #expect(hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(11.2)) == nil)
        #expect(hold.expiry(after: start.addingTimeInterval(11.2)) == nil)
        #expect(hold.update(entryID: "b", real: "B", isLoading: false, at: start.addingTimeInterval(14)) == "B",
                "a cover that arrives late still shows")
    }

    @Test func skippingAgainWhileLoadingNeverBringsBackAnOlderCover() {
        var hold = CoverHold<String>(window: 1.0)
        _ = hold.update(entryID: "a", real: "A", isLoading: false, at: start)
        _ = hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(10))
        _ = hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(11.5))
        #expect(hold.update(entryID: "c", real: nil, isLoading: true, at: start.addingTimeInterval(12)) == nil,
                "A belongs to two songs back")
    }

    @Test func quickSecondSkipDoesNotLendACoverFromTwoSongsBack() {
        var hold = CoverHold<String>(window: 1.0)
        _ = hold.update(entryID: "a", real: "A", isLoading: false, at: start)
        #expect(hold.update(entryID: "b", real: nil, isLoading: true, at: start.addingTimeInterval(10)) == "A")
        #expect(hold.update(entryID: "c", real: nil, isLoading: true, at: start.addingTimeInterval(10.3)) == nil)
    }

    @Test func songWithoutArtworkShowsNone() {
        var hold = CoverHold<String>(window: 1.0)
        _ = hold.update(entryID: "a", real: "A", isLoading: false, at: start)
        #expect(hold.update(entryID: "b", real: nil, isLoading: false, at: start.addingTimeInterval(3)) == nil)
    }
}
