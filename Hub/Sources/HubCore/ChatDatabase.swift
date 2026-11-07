import CommsKit
import Foundation

/// Reads conversations and messages from Messages' chat.db.
public final class ChatDatabase {
    public static let defaultPath = NSHomeDirectory() + "/Library/Messages/chat.db"

    let connection: SQLiteConnection
    let contacts: ContactsBook

    /// The Contacts picture for a phone number or email, if that person has one.
    public func contactPhoto(for handle: String) -> Data? { contacts.photo(for: handle) }

    public init(path: String = ChatDatabase.defaultPath, contacts: ContactsBook = ContactsBook()) throws {
        connection = try SQLiteConnection(path: path)
        self.contacts = contacts
        var columns: [String] = []
        try connection.query("PRAGMA table_info(message)") { if let name = $0.text(1) { columns.append(name) } }
        hasEmojiColumn = columns.contains("associated_message_emoji")
        var chatColumns: [String] = []
        try connection.query("PRAGMA table_info(chat)") { if let name = $0.text(1) { chatColumns.append(name) } }
        hasGroupIDColumn = chatColumns.contains("group_id")
    }

    /// Newer macOS stores the emoji of a custom reaction in its own column.
    let hasEmojiColumn: Bool
    /// Messages' own conversation ID, used to open a chat (`ChatAddress`). Small test databases leave it out.
    let hasGroupIDColumn: Bool

    /// Newest conversations first.
    public func conversations(limit: Int) throws -> [CommsConversation] {
        var found: [(rowID: Int64, conversation: CommsConversation, hasName: Bool)] = []
        let sql = """
            SELECT c.ROWID, c.guid, c.display_name, c.chat_identifier, c.service_name, c.style,
                   (SELECT MAX(cmj.message_date) FROM chat_message_join cmj JOIN message m ON m.ROWID = cmj.message_id
                     WHERE cmj.chat_id = c.ROWID AND \(Reactions.notTapback)),
                   (SELECT COUNT(*) FROM chat_message_join cmj JOIN message m ON m.ROWID = cmj.message_id
                     WHERE cmj.chat_id = c.ROWID AND m.is_from_me = 0 AND m.is_read = 0 AND m.item_type = 0 AND \(Reactions.notTapback))
            FROM chat c
            WHERE EXISTS (SELECT 1 FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID)
            ORDER BY 7 DESC
            LIMIT ?
            """
        try connection.query(sql, [.int(Int64(limit))]) { row in
            let identifier = row.text(3) ?? ""
            let name = row.text(2) ?? ""
            let conversation = CommsConversation(
                id: row.text(1) ?? "",
                title: name.isEmpty ? identifier : name,
                participants: [],
                isGroup: row.int(5) == 43,
                service: CommsService(rawValue: row.text(4) ?? "") ?? .unknown,
                lastMessagePreview: "",
                lastMessageDate: AppleDate.date(row.int(6)),
                unreadCount: Int(row.int(7))
            )
            found.append((row.int(0), conversation, !name.isEmpty))
        }
        return try found.map { rowID, conversation, hasName in
            var filled = conversation
            filled.participants = try participants(chatRowID: rowID)
            filled.title = title(for: conversation, participants: filled.participants, hasName: hasName)
            filled.lastMessagePreview = try messages(chatRowID: rowID, before: nil, limit: 1).first?.text ?? ""
            return filled
        }
    }

    /// One page of messages, newest first. `before` pages backward in time.
    public func messages(inConversation guid: String, before: Date?, limit: Int) throws -> [CommsMessage] {
        guard let rowID = try chatRowID(guid: guid) else { return [] }
        return try messages(chatRowID: rowID, before: before, limit: limit)
    }

    private func chatRowID(guid: String) throws -> Int64? {
        var rowID: Int64?
        try connection.query("SELECT ROWID FROM chat WHERE guid = ?", [.text(guid)]) { rowID = $0.int(0) }
        return rowID
    }

    /// A saved group name wins. Otherwise people are named from Contacts, or by their number.
    private func title(for conversation: CommsConversation, participants: [String], hasName: Bool) -> String {
        if conversation.isGroup {
            if hasName { return conversation.title }
            let names = participants.map { contacts.name(for: $0) ?? $0 }
            let shown = names.prefix(3).joined(separator: ", ")
            return names.count > 3 ? shown + " +\(names.count - 3)" : shown
        }
        return contacts.name(for: conversation.title) ?? conversation.title
    }

    private func participants(chatRowID: Int64) throws -> [String] {
        var handles: [String] = []
        let sql = "SELECT h.id FROM chat_handle_join j JOIN handle h ON h.ROWID = j.handle_id WHERE j.chat_id = ?"
        try connection.query(sql, [.int(chatRowID)]) { if let id = $0.text(0) { handles.append(id) } }
        return handles
    }

    fileprivate static let messageColumns = """
        m.ROWID, m.guid, m.text, m.attributedBody, m.date, m.is_from_me, m.is_read, h.id, c.guid,
        m.balloon_bundle_id, m.payload_data
        """

    /// A message row before its attachments and link are filled in. Those need more queries,
    /// which cannot run while this statement is still being read.
    fileprivate struct RawMessage {
        var rowID: Int64
        var message: CommsMessage
        var balloon: String?
        var payload: Data?
    }

    fileprivate func raw(_ row: Row) -> RawMessage {
        let fromMe = row.int(5) == 1
        let message = CommsMessage(
            id: row.text(1) ?? "",
            conversationID: row.text(8) ?? "",
            sender: fromMe ? nil : row.text(7),
            senderName: fromMe ? nil : row.text(7).flatMap { contacts.name(for: $0) },
            text: MessageText.resolve(text: row.text(2), attributedBody: row.data(3)),
            date: AppleDate.date(row.int(4)),
            isFromMe: fromMe,
            isRead: row.int(6) == 1
        )
        return RawMessage(rowID: row.int(0), message: message, balloon: row.text(9), payload: row.data(10))
    }

    /// Adds visible attachments, and turns a rich link into one card.
    fileprivate func finish(_ raw: RawMessage) throws -> CommsMessage {
        var message = raw.message
        let all = try attachments(messageRowID: raw.rowID)
        message.attachments = all.filter { !$0.isHidden }.map(\.attachment)
        message.reactions = try reactions(toMessage: message.id)
        if raw.balloon?.contains("URLBalloonProvider") == true,
           let payload = raw.payload.flatMap(LinkPayload.init(data:)), let url = payload.url {
            let image = payload.imageIndex.flatMap { all.indices.contains($0) ? all[$0] : nil }
                ?? all.first { $0.isHidden && $0.attachment.mimeType.hasPrefix("image/") }
            message.link = CommsLink(url: url, title: payload.title, imageAttachmentID: image?.attachment.id)
        }
        return message
    }

    private func messages(chatRowID: Int64, before: Date?, limit: Int) throws -> [CommsMessage] {
        var rows: [RawMessage] = []
        let sql = """
            SELECT \(Self.messageColumns)
            FROM chat_message_join cmj
            JOIN message m ON m.ROWID = cmj.message_id
            JOIN chat c ON c.ROWID = cmj.chat_id
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE cmj.chat_id = ? AND m.item_type = 0 AND \(Reactions.notTapback) AND m.date < ?
            ORDER BY m.date DESC
            LIMIT ?
            """
        let cutoff = before.map(AppleDate.raw) ?? Int64.max
        try connection.query(sql, [.int(chatRowID), .int(cutoff), .int(Int64(limit))]) { rows.append(raw($0)) }
        return try rows.map(finish)
    }

    fileprivate struct AttachmentRow {
        var attachment: CommsAttachment
        var isHidden: Bool
    }

    fileprivate func attachments(messageRowID: Int64) throws -> [AttachmentRow] {
        var found: [AttachmentRow] = []
        let sql = """
            SELECT a.guid, a.mime_type, a.transfer_name, a.hide_attachment, a.filename
            FROM message_attachment_join j JOIN attachment a ON a.ROWID = j.attachment_id
            WHERE j.message_id = ?
            ORDER BY j.ROWID
            """
        try connection.query(sql, [.int(messageRowID)]) { row in
            let name = row.text(2) ?? ""
            let mimeType = row.text(1) ?? ""
            let isHidden = row.int(3) == 1 || name.hasSuffix(".pluginPayloadAttachment")
            var attachment = CommsAttachment(id: row.text(0) ?? "", mimeType: mimeType, name: name)
            if !isHidden, let file = row.text(4).flatMap(Self.messagesFile), let size = MediaSize.of(file, mimeType: mimeType) {
                attachment.width = Int(size.width.rounded())
                attachment.height = Int(size.height.rounded())
            }
            found.append(AttachmentRow(attachment: attachment, isHidden: isHidden))
        }
        return found
    }
}

// MARK: Change detection for the event stream

extension ChatDatabase {
    /// The highest message row, so a watcher can ask for what came after it.
    public func latestMessageRowID() throws -> Int64 {
        var rowID: Int64 = 0
        try connection.query("SELECT COALESCE(MAX(ROWID), 0) FROM message") { rowID = $0.int(0) }
        return rowID
    }

    /// Messages added after `rowID`, oldest first, with the row each one has.
    public func messages(afterRowID rowID: Int64, limit: Int = 200) throws -> [(rowID: Int64, message: CommsMessage)] {
        var rows: [RawMessage] = []
        let sql = """
            SELECT \(Self.messageColumns)
            FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            JOIN chat c ON c.ROWID = cmj.chat_id
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.ROWID > ? AND m.item_type = 0 AND \(Reactions.notTapback)
            ORDER BY m.ROWID ASC
            LIMIT ?
            """
        try connection.query(sql, [.int(rowID), .int(Int64(limit))]) { rows.append(raw($0)) }
        return try rows.map { (rowID: $0.rowID, message: try finish($0)) }
    }

    /// Unread incoming messages per chat GUID, for chats that have any.
    public func unreadCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        let sql = """
            SELECT c.guid, COUNT(*)
            FROM chat_message_join cmj JOIN message m ON m.ROWID = cmj.message_id JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE m.is_from_me = 0 AND m.is_read = 0 AND m.item_type = 0 AND \(Reactions.notTapback)
            GROUP BY c.guid
            """
        try connection.query(sql) { row in counts[row.text(0) ?? ""] = Int(row.int(1)) }
        return counts
    }
}

extension ChatDatabase {
    /// What it takes to show a chat in Messages (`ChatAddress`). Nil for a GUID chat.db does not have.
    public func address(ofChat guid: String) throws -> ChatAddress? {
        let groupColumn = hasGroupIDColumn ? "group_id" : "NULL"
        let sql = "SELECT style, service_name, chat_identifier, \(groupColumn) FROM chat WHERE guid = ?"
        var found: ChatAddress?
        try connection.query(sql, [.text(guid)]) { row in
            found = ChatAddress(
                guid: guid,
                isGroup: row.int(0) == 43,
                service: row.text(1) ?? "",
                identifier: row.text(2) ?? "",
                groupID: row.text(3)
            )
        }
        return found
    }
}

extension ChatDatabase {
    /// The Messages login that owns most chats, such as `kyle@example.com`.
    /// chat.db prefixes it with `E:` (email) or `P:` (phone), and some chats have none.
    public func accountLogin() throws -> String? {
        var login: String?
        let sql = """
            SELECT account_login FROM chat WHERE length(account_login) > 2
            GROUP BY account_login ORDER BY COUNT(*) DESC LIMIT 1
            """
        try connection.query(sql) { login = $0.text(0) }
        return login.map { String($0.dropFirst(2)) }
    }
}

extension ChatDatabase {
    /// Where an attachment lives on disk, with its type. Nil when unknown or the file is gone.
    /// Only files under Messages' own Attachments folder are ever returned.
    public func attachmentFile(guid: String) throws -> (url: URL, mimeType: String)? {
        var found: (String, String)?
        try connection.query("SELECT filename, mime_type, uti FROM attachment WHERE guid = ?", [.text(guid)]) { row in
            if let name = row.text(0) { found = (name, row.text(1) ?? "") }
        }
        guard let (name, mime) = found, let url = Self.messagesFile(name) else { return nil }
        return (url, mime.isEmpty ? Self.mimeType(for: url) : mime)
    }

    /// The file for an attachment's `filename`, only when it is inside Messages' attachments folder and exists.
    static func messagesFile(_ name: String) -> URL? {
        let url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
        let root = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Messages/Attachments").resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(root), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "heic": "image/heic"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "mov": "video/quicktime"
        case "mp4", "m4v": "video/mp4"
        default: "application/octet-stream"
        }
    }
}
