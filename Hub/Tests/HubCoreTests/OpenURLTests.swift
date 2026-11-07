import SQLite3
import XCTest
@testable import HubCore

/// The URL the hub opens in Messages to mark a chat read, for each kind of chat in `Hub/fixtures/chat_kinds.sql`.
final class OpenURLTests: XCTestCase {
    private func fixtureDatabase() throws -> (ChatDatabase, URL) {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/chat_kinds.sql")
        let sql = try String(contentsOf: fixture, encoding: .utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-kinds-\(UUID().uuidString).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        return (try ChatDatabase(path: url.path), url)
    }

    private func openURL(_ guid: String, in database: ChatDatabase) throws -> String? {
        try database.address(ofChat: guid)?.openURL?.absoluteString
    }

    func testEachKindOfChatOpensItsOwnConversation() throws {
        let (database, file) = try fixtureDatabase()
        defer { try? FileManager.default.removeItem(at: file) }

        // One person over iMessage: as before, by their number or email, also with a macOS 26 GUID.
        XCTAssertEqual(try openURL("iMessage;-;+15555550101", in: database), "imessage://+15555550101")
        XCTAssertEqual(try openURL("any;-;fixture.friend@example.com", in: database), "imessage://fixture.friend@example.com")
        // SMS and RCS: that exact chat by its group ID, so not an iMessage chat with the same number.
        XCTAssertEqual(try openURL("SMS;-;+15555550103", in: database), "messages://open?groupid=7C1D2E3F-0000-4000-8000-000000000103")
        XCTAssertEqual(try openURL("any;-;+15555550104", in: database), "messages://open?groupid=7C1D2E3F-0000-4000-8000-000000000104")
        // SMS without a group ID: the number, through the sms scheme.
        XCTAssertEqual(try openURL("SMS;-;+15555550105", in: database), "sms:+15555550105")
        // A group by its group ID, never by its chat123 identifier.
        XCTAssertEqual(try openURL("iMessage;+;chat100000000000000001", in: database), "messages://open?groupid=7C1D2E3F-0000-4000-8000-000000000106")
        // A group without one is not opened at all.
        XCTAssertNil(try openURL("any;+;chat100000000000000002", in: database))
        XCTAssertNil(try database.address(ofChat: "iMessage;-;+15555550199"), "a chat chat.db does not have")
    }

    func testADatabaseWithoutGroupIDsStillOpensOnePersonChats() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-old-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = """
            CREATE TABLE chat (guid TEXT, style INT, service_name TEXT, chat_identifier TEXT);
            CREATE TABLE message (associated_message_type INT);
            INSERT INTO chat VALUES ('iMessage;-;+15555550101', 45, 'iMessage', '+15555550101'), ('iMessage;+;chat1', 43, 'iMessage', 'chat1');
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let database = try ChatDatabase(path: url.path)
        XCTAssertEqual(try openURL("iMessage;-;+15555550101", in: database), "imessage://+15555550101")
        XCTAssertNil(try openURL("iMessage;+;chat1", in: database))
    }
}
