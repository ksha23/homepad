import SQLite3
import XCTest
@testable import CommsKit
@testable import HubCore

/// Builds a tiny chat.db with one message, tapbacks on it, and reads it back through ChatDatabase.
final class ReactionTests: XCTestCase {
    private func makeDatabase() throws -> (ChatDatabase, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reactions-\(UUID().uuidString).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
            CREATE TABLE chat (guid TEXT, display_name TEXT, chat_identifier TEXT, service_name TEXT, style INT, account_login TEXT);
            CREATE TABLE handle (id TEXT);
            CREATE TABLE message (guid TEXT, text TEXT, attributedBody BLOB, date INT, is_from_me INT, is_read INT, handle_id INT,
                balloon_bundle_id TEXT, payload_data BLOB, item_type INT DEFAULT 0, associated_message_guid TEXT,
                associated_message_type INT DEFAULT 0, associated_message_emoji TEXT);
            CREATE TABLE chat_message_join (chat_id INT, message_id INT, message_date INT);
            CREATE TABLE chat_handle_join (chat_id INT, handle_id INT);
            CREATE TABLE attachment (guid TEXT, mime_type TEXT, transfer_name TEXT, hide_attachment INT, filename TEXT, uti TEXT);
            CREATE TABLE message_attachment_join (message_id INT, attachment_id INT);
            INSERT INTO handle (id) VALUES ('+15555550101'), ('+15555550102');
            INSERT INTO chat VALUES ('chat-1', '', '+15555550101', 'iMessage', 45, 'E:fixture@example.com');
            INSERT INTO chat_handle_join VALUES (1, 1);
            -- rowid, guid, text, date, from_me, read, handle, associated guid, type, emoji
            INSERT INTO message (guid, text, date, is_from_me, is_read, handle_id, associated_message_guid, associated_message_type, associated_message_emoji) VALUES
              ('m1', 'Dinner at seven', 100, 0, 0, 1, NULL, 0, NULL),
              ('r1', 'Loved an item', 101, 0, 0, 1, 'p:0/m1', 2000, NULL),
              ('r2', 'Liked an item', 102, 0, 0, 2, 'bp:m1', 2001, NULL),
              ('r3', 'Laughed at an item', 103, 1, 1, 0, 'p:0/m1', 2003, NULL),
              ('r4', 'Removed a like', 104, 0, 0, 2, 'bp:m1', 3001, NULL),
              ('r5', 'Reacted with an emoji', 105, 0, 0, 1, 'p:0/m1', 2006, '🎉');
            INSERT INTO chat_message_join (chat_id, message_id, message_date) SELECT 1, rowid, date FROM message;
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        return (try ChatDatabase(path: url.path), url)
    }

    func testTapbacksAttachToTheirMessageAndStayOutOfTheList() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let messages = try database.messages(inConversation: "chat-1", before: nil, limit: 20)
        XCTAssertEqual(messages.map(\.id), ["m1"])
        let reactions = messages[0].reactions
        // The like from the second person was removed, so three remain, oldest first.
        XCTAssertEqual(reactions.map(\.kind), ["love", "laugh", "emoji"])
        XCTAssertEqual(reactions.map(\.isFromMe), [false, true, false])
        XCTAssertEqual(reactions[0].sender, "+15555550101")
        XCTAssertNil(reactions[1].sender)
        XCTAssertEqual(reactions[2].emoji, "🎉")
    }

    func testTapbacksDoNotBecomePreviewOrUnread() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let conversation = try XCTUnwrap(database.conversations(limit: 5).first)
        XCTAssertEqual(conversation.lastMessagePreview, "Dinner at seven")
        XCTAssertEqual(conversation.unreadCount, 1)
        XCTAssertEqual(try database.unreadCounts()["chat-1"], 1)
        XCTAssertEqual(try database.messages(afterRowID: 0).map(\.message.id), ["m1"])
    }

    func testLatestEventPerPersonAndKindWins() {
        func event(_ type: Int64, _ sender: String) -> Reactions.Event {
            Reactions.Event(type: type, emoji: nil, isFromMe: false, sender: sender, senderName: nil)
        }
        XCTAssertEqual(Reactions.fold([event(2000, "a"), event(3000, "a"), event(2000, "a")]).count, 1)
        XCTAssertEqual(Reactions.fold([event(2000, "a"), event(3000, "a")]).count, 0)
        XCTAssertEqual(Reactions.fold([event(2000, "a"), event(2001, "a")]).count, 2)
    }
}
