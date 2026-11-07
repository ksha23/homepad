import Foundation

/// Merge rules for the Family Board, shared by the peer link and CloudKit.
/// The merge is commutative, associative and idempotent, so devices converge
/// no matter which order updates arrive in.
public enum BoardMerge {
    /// Tombstones older than this are dropped for good.
    public static let tombstoneLifetime: TimeInterval = 30 * 24 * 3600

    /// The surviving version of one note: newest edit wins. On an exact tie a
    /// deletion wins, then the higher device ID, then the text, so every device picks the same one.
    public static func winner(_ a: BoardNote, _ b: BoardNote) -> BoardNote {
        if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt ? a : b }
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        if a.modifiedBy != b.modifiedBy { return a.modifiedBy > b.modifiedBy ? a : b }
        return a.text >= b.text ? a : b
    }

    /// Union of both sets, keeping the winner for each note ID. Sorted by creation.
    public static func merge(_ local: [BoardNote], _ incoming: [BoardNote]) -> [BoardNote] {
        var byID: [UUID: BoardNote] = [:]
        for note in local + incoming {
            byID[note.id] = byID[note.id].map { winner($0, note) } ?? note
        }
        return byID.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// True when `local` holds a note the sender of `incoming` lacks or has an older version of,
    /// so we should send our state back.
    public static func hasNewerThan(_ incoming: [BoardNote], local: [BoardNote]) -> Bool {
        let theirs = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: winner)
        return local.contains { note in
            guard let other = theirs[note.id] else { return true }
            return winner(note, other) == note && note != other
        }
    }

    /// Notes to show: live ones, pinned first, then newest first.
    public static func visible(_ notes: [BoardNote]) -> [BoardNote] {
        notes.filter { !$0.isDeleted }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    /// Drops tombstones old enough that every device has seen them.
    public static func pruned(_ notes: [BoardNote], now: Date = Date()) -> [BoardNote] {
        notes.filter { !$0.isDeleted || now.timeIntervalSince($0.modifiedAt) < tombstoneLifetime }
    }
}
