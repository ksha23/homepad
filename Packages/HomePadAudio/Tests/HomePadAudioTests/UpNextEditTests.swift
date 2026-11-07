import Foundation
import Testing
@testable import HomePadAudio

/// Up Next's edits, on plain arrays, with offsets counted from the first upcoming song.
@Suite struct UpNextEditTests {
    private let upcoming = ["a", "b", "c", "d", "e"]

    @Test func movesLikeAListDoes() {
        // Drag "a" below "c": the destination counts "a" itself.
        #expect(UpNextEdit.moved(upcoming, from: [0], to: 3) == ["b", "c", "a", "d", "e"])
        // Drag "e" to the top.
        #expect(UpNextEdit.moved(upcoming, from: [4], to: 0) == ["e", "a", "b", "c", "d"])
        // Two songs together keep their order.
        #expect(UpNextEdit.moved(upcoming, from: [1, 3], to: 5) == ["a", "c", "e", "b", "d"])
        // To the end.
        #expect(UpNextEdit.moved(upcoming, from: [0], to: 5) == ["b", "c", "d", "e", "a"])
    }

    @Test func movingNothingOrOutOfRangeChangesNothing() {
        #expect(UpNextEdit.moved(upcoming, from: [], to: 2) == upcoming)
        #expect(UpNextEdit.moved(upcoming, from: [9], to: 0) == upcoming)
        #expect(UpNextEdit.moved([String](), from: [0], to: 0) == [])
    }

    @Test func removesTheChosenSongs() {
        #expect(UpNextEdit.removed(upcoming, at: [0, 2]) == ["b", "d", "e"])
        #expect(UpNextEdit.removed(upcoming, at: []) == upcoming)
        #expect(UpNextEdit.removed(upcoming, at: [7]) == upcoming)
    }

    @Test func playNextGoesFirstAndPlayLaterLast() {
        #expect(UpNextEdit.inserted(["x", "y"], into: upcoming, at: .next) == ["x", "y", "a", "b", "c", "d", "e"])
        #expect(UpNextEdit.inserted(["x"], into: upcoming, at: .later) == ["a", "b", "c", "d", "e", "x"])
        #expect(UpNextEdit.inserted(["x"], into: [], at: .next) == ["x"])
    }

    @Test func upcomingIsEverythingAfterTheCurrentSong() {
        #expect(UpNextEdit.upcomingRange(count: 6, current: 1) == 2..<6)
        #expect(UpNextEdit.upcomingRange(count: 6, current: 5) == 6..<6)
        #expect(UpNextEdit.upcomingRange(count: 6, current: nil) == 0..<6)
        #expect(UpNextEdit.upcomingRange(count: 0, current: 3) == 0..<0)
    }
}
