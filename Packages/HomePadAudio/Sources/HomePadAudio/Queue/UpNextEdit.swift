import Foundation

/// Edits to the songs after the current one, worked out on plain arrays so the
/// rules are unit tested without MusicKit. Offsets count from the first
/// upcoming song, as the Up Next list shows them.
enum UpNextEdit {
    /// Moves the songs at `offsets` to before `destination`, like a list's `onMove`.
    static func moved<T>(_ upcoming: [T], from offsets: IndexSet, to destination: Int) -> [T] {
        let valid = offsets.filter { upcoming.indices.contains($0) }
        guard !valid.isEmpty else { return upcoming }
        let moving = valid.map { upcoming[$0] }
        var rest: [T] = []
        rest.reserveCapacity(upcoming.count)
        for (index, item) in upcoming.enumerated() where !valid.contains(index) { rest.append(item) }
        // The destination counts the moved songs too, so shift it past those taken from before it.
        let target = max(0, min(rest.count, destination - valid.filter { $0 < destination }.count))
        rest.insert(contentsOf: moving, at: target)
        return rest
    }

    /// Removes the songs at `offsets`.
    static func removed<T>(_ upcoming: [T], at offsets: IndexSet) -> [T] {
        upcoming.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Where new songs go: right after the current one, or at the end.
    enum Position: Sendable {
        case next, later
    }

    /// Adds `items` after the current song or at the end of the queue.
    static func inserted<T>(_ items: [T], into upcoming: [T], at position: Position) -> [T] {
        switch position {
        case .next: items + upcoming
        case .later: upcoming + items
        }
    }

    /// The range of `count` entries that follows `current`, the part Up Next edits.
    /// With no current entry, the whole queue is upcoming.
    static func upcomingRange(count: Int, current: Int?) -> Range<Int> {
        let start = current.map { min(count, $0 + 1) } ?? 0
        return start..<count
    }
}
