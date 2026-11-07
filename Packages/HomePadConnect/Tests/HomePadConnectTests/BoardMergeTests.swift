import Foundation
import Testing
@testable import HomePadConnect

@Suite struct BoardMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, id: UUID = UUID(), at offset: TimeInterval = 0, by device: String = "pad",
                      deleted: Bool = false) -> BoardNote {
        BoardNote(id: id, text: text, author: "Kyle", createdAt: t0, modifiedAt: t0.addingTimeInterval(offset),
                  modifiedBy: device, isDeleted: deleted)
    }

    @Test func newerEditWins() {
        let id = UUID()
        let old = note("Buy milk", id: id, at: 0)
        let new = note("Buy oat milk", id: id, at: 5, by: "phone")
        #expect(BoardMerge.merge([old], [new]).map(\.text) == ["Buy oat milk"])
        #expect(BoardMerge.merge([new], [old]).map(\.text) == ["Buy oat milk"])
    }

    @Test func newerDeletionRemovesTheNoteEverywhere() {
        let id = UUID()
        let live = note("Dentist 3pm", id: id, at: 0)
        let tombstone = note("Dentist 3pm", id: id, at: 10, by: "phone", deleted: true)
        let merged = BoardMerge.merge([live], [tombstone])
        #expect(merged.count == 1 && merged[0].isDeleted)
        #expect(BoardMerge.visible(merged).isEmpty)
    }

    @Test func editAfterDeletionRevivesTheNote() {
        let id = UUID()
        let tombstone = note("x", id: id, at: 10, deleted: true)
        let revived = note("x again", id: id, at: 20, by: "phone")
        #expect(BoardMerge.visible(BoardMerge.merge([tombstone], [revived])).map(\.text) == ["x again"])
    }

    @Test func exactTiesResolveTheSameWayOnEveryDevice() {
        let id = UUID()
        let fromPad = note("pad text", id: id, at: 3, by: "pad")
        let fromPhone = note("phone text", id: id, at: 3, by: "phone")
        #expect(BoardMerge.winner(fromPad, fromPhone) == BoardMerge.winner(fromPhone, fromPad))
        // Deletion wins a tie.
        let deleted = note("pad text", id: id, at: 3, by: "aaa", deleted: true)
        #expect(BoardMerge.winner(fromPhone, deleted).isDeleted)
    }

    @Test func mergeIsCommutativeAssociativeAndIdempotent() {
        let shared = UUID()
        let a = [note("a1"), note("shared v1", id: shared, at: 1)]
        let b = [note("b1"), note("shared v2", id: shared, at: 2, by: "phone")]
        let c = [note("c1"), note("shared v0", id: shared, at: 0, by: "mac", deleted: true)]

        #expect(BoardMerge.merge(a, b) == BoardMerge.merge(b, a))
        #expect(BoardMerge.merge(BoardMerge.merge(a, b), c) == BoardMerge.merge(a, BoardMerge.merge(b, c)))
        let ab = BoardMerge.merge(a, b)
        #expect(BoardMerge.merge(ab, ab) == ab)
        #expect(BoardMerge.merge(ab, c).count == 4)   // a1, b1, c1 and the shared note
        #expect(BoardMerge.merge(ab, c).first { $0.text.hasPrefix("shared") }?.text == "shared v2")
    }

    @Test func detectsWhenWeShouldReplyWithOurState() {
        let id = UUID()
        let ours = [note("v2", id: id, at: 2)]
        #expect(BoardMerge.hasNewerThan([note("v1", id: id, at: 1)], local: ours))
        #expect(!BoardMerge.hasNewerThan(ours, local: ours))
        #expect(!BoardMerge.hasNewerThan([note("v3", id: id, at: 3)], local: ours))
        #expect(BoardMerge.hasNewerThan([], local: ours))
    }

    @Test func visibleSortsPinnedFirstThenNewest() {
        var pinned = note("pinned", at: 0)
        pinned.isPinned = true
        let newest = note("newest", at: 9)
        let older = note("older", at: 4)
        #expect(BoardMerge.visible([older, newest, pinned]).map(\.text) == ["pinned", "newest", "older"])
    }

    @Test func oldTombstonesArePruned() {
        let recent = note("recent", at: 0, deleted: true)
        let ancient = BoardNote(text: "ancient", author: "Kyle", createdAt: t0.addingTimeInterval(-90 * 24 * 3600), modifiedBy: "pad", isDeleted: true)
        let live = BoardNote(text: "live", author: "Kyle", createdAt: t0.addingTimeInterval(-90 * 24 * 3600), modifiedBy: "pad")
        #expect(Set(BoardMerge.pruned([recent, ancient, live], now: t0).map(\.text)) == ["recent", "live"])
    }

    @Test func touchAlwaysMovesTimeForward() {
        var n = note("x", at: 100)
        n.touch(by: "phone", at: t0)   // clock behind the note's time
        #expect(n.modifiedAt > t0.addingTimeInterval(100))
        #expect(n.modifiedBy == "phone")
    }
}
