import CommsKit
import Foundation

/// What one person has read on this iPad: for each conversation, the date of the newest message
/// they have had on screen here.
///
/// The Mac marks a chat read only when Messages can show it, which a locked Mac cannot. So HomePad
/// keeps its own record and does not wait for the Mac. It is saved in that person's encrypted cache
/// (`CommsCache`) on this iPad only, and never sent anywhere. See docs/COMMS.md, "Read state".
struct ReadMarkers: Codable, Equatable, Sendable {
    /// Conversation ID to the date of the newest message seen in it.
    private(set) var seen: [String: Date] = [:]

    /// How many markers the cache keeps, the most recent ones.
    static let limit = 200

    /// Everything in the conversation up to `date` has been seen. A marker never moves back.
    mutating func markSeen(_ id: String, through date: Date) {
        if let old = seen[id], old >= date { return }
        seen[id] = date
    }

    func marker(for id: String) -> Date? { seen[id] }

    /// The unread count HomePad shows for a conversation.
    ///
    /// - The hub says it is read (on the Mac, the iPhone or another device): 0.
    /// - No marker: the hub's count.
    /// - Nothing newer than the marker: 0.
    /// - Otherwise the unread messages from other people newer than the marker, counted in the
    ///   thread HomePad holds, never more than the hub's count. If that thread does not reach back
    ///   to the marker, HomePad cannot tell and shows the hub's count.
    ///
    /// - Parameters:
    ///   - hubCount: the hub's own unread count for the conversation.
    ///   - newest: the date of the conversation's newest message.
    ///   - thread: the messages HomePad holds for it, oldest first, if any.
    func unreadCount(_ id: String, hubCount: Int, newest: Date, thread: [CommsMessage]?) -> Int {
        guard hubCount > 0 else { return 0 }
        guard let marker = seen[id] else { return hubCount }
        if newest <= marker { return 0 }
        guard let thread, let oldest = thread.first?.date, oldest <= marker else { return hubCount }
        let newer = thread.filter { !$0.isFromMe && !$0.isRead && $0.date > marker }.count
        return min(newer, hubCount)
    }

    /// The `limit` most recent markers, so the saved copy stays small.
    func trimmed() -> ReadMarkers {
        guard seen.count > Self.limit else { return self }
        let kept = seen.sorted { $0.value > $1.value }.prefix(Self.limit)
        return ReadMarkers(seen: Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) }))
    }
}
