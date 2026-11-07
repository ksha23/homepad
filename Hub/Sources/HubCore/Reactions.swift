import CommsKit
import Foundation

/// Tapback reactions in chat.db. Each one is its own `message` row that points at the
/// message it reacts to, so the hub hides those rows and attaches them to their targets.
enum Reactions {
    /// Row types: 2000...2005 add a tapback, 3000...3005 remove it, 2006 and 3006 are emoji
    /// reactions. 2007 and 3007 are reserved for stickers and also never shown as messages.
    static let notTapback = "COALESCE(m.associated_message_type, 0) NOT BETWEEN 2000 AND 3007"
    static let tapbackOnly = "m.associated_message_type BETWEEN 2000 AND 3006"

    /// One add or remove row, oldest first.
    struct Event {
        var type: Int64
        var emoji: String?
        var isFromMe: Bool
        var sender: String?
        var senderName: String?
    }

    /// The `associated_message_guid` values that can point at `guid`: `bp:` for the whole
    /// bubble, and `p:N/` for part N of a message with several parts.
    static func targets(of guid: String) -> [String] {
        [guid, "bp:" + guid] + (0..<4).map { "p:\($0)/" + guid }
    }

    static func kind(of type: Int64) -> String? {
        switch type % 1000 {
        case 0: "love"
        case 1: "like"
        case 2: "dislike"
        case 3: "laugh"
        case 4: "emphasize"
        case 5: "question"
        case 6: "emoji"
        default: nil
        }
    }

    /// The latest add or remove per person and tapback wins, so a removal cancels an earlier add.
    static func fold(_ events: [Event]) -> [CommsReaction] {
        var kept: [(key: String, reaction: CommsReaction)] = []
        for event in events {
            guard let kind = kind(of: event.type) else { continue }
            let emoji = kind == "emoji" ? event.emoji : nil
            if kind == "emoji", emoji == nil { continue }
            let who = event.isFromMe ? "me" : (event.sender ?? "")
            let key = "\(who)|\(kind)|\(emoji ?? "")"
            kept.removeAll { $0.key == key }
            if event.type < 3000 {
                let reaction = CommsReaction(
                    kind: kind, emoji: emoji, sender: event.isFromMe ? nil : event.sender,
                    senderName: event.isFromMe ? nil : event.senderName, isFromMe: event.isFromMe)
                kept.append((key, reaction))
            }
        }
        return kept.map(\.reaction)
    }
}

extension ChatDatabase {
    /// The tapbacks currently on one message.
    func reactions(toMessage guid: String) throws -> [CommsReaction] {
        let targets = Reactions.targets(of: guid)
        let places = targets.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT m.associated_message_type, \(hasEmojiColumn ? "m.associated_message_emoji" : "NULL"), m.is_from_me, h.id
            FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.associated_message_guid IN (\(places)) AND \(Reactions.tapbackOnly)
            ORDER BY m.date, m.ROWID
            """
        var events: [Reactions.Event] = []
        try connection.query(sql, targets.map { .text($0) }) { row in
            let handle = row.text(3)
            events.append(Reactions.Event(
                type: row.int(0), emoji: row.text(1), isFromMe: row.int(2) == 1, sender: handle,
                senderName: handle.flatMap { contacts.name(for: $0) }))
        }
        return Reactions.fold(events)
    }
}
