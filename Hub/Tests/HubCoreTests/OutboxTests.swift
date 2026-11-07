import XCTest
@testable import HubCore

final class OutboxTests: XCTestCase {
    private func makeOutbox() -> Outbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-test-\(UUID().uuidString)", isDirectory: true)
        return Outbox(directory: root)
    }

    func testStageWritesPrivateFileAndDiscardRemovesIt() throws {
        let outbox = makeOutbox()
        defer { try? FileManager.default.removeItem(at: outbox.directory) }
        let file = try outbox.stage(Data("hello".utf8), filename: "a.jpg")
        XCTAssertEqual(try Data(contentsOf: file), Data("hello".utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        outbox.discard(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }

    func testDiscardIgnoresFilesOutsideTheOutbox() throws {
        let outbox = makeOutbox()
        let other = makeOutbox()
        defer {
            try? FileManager.default.removeItem(at: outbox.directory)
            try? FileManager.default.removeItem(at: other.directory)
        }
        let foreign = try other.stage(Data("x".utf8), filename: "b.png")
        outbox.discard(foreign)
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    func testPurgeClearsLeftovers() throws {
        let outbox = makeOutbox()
        defer { try? FileManager.default.removeItem(at: outbox.directory) }
        let file = try outbox.stage(Data("x".utf8), filename: "c.png")
        outbox.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

final class SendCommandTests: XCTestCase {
    func testPathAndChatTravelAsArguments() {
        let file = URL(fileURLWithPath: "/tmp/x\"; do shell script \"boom.jpg")
        let arguments = MessagesActions.sendFileArguments(file: file, conversation: "iMessage;-;+15551234567")
        XCTAssertEqual(arguments, [file.path, "iMessage;-;+15551234567"])
        XCTAssertFalse(MessagesActions.sendFileScript.contains("boom"))
        XCTAssertTrue(MessagesActions.sendFileScript.contains("POSIX file (item 1 of argv)"))
        XCTAssertTrue(MessagesActions.sendFileScript.contains("chat id (item 2 of argv)"))
    }

    func testUploadNameIsSanitizedAndGetsAnExtension() {
        XCTAssertEqual(HubServer.uploadName(header: "..%2F..%2Fevil.jpg", contentType: "image/jpeg"), "_.._evil.jpg")
        XCTAssertEqual(HubServer.uploadName(header: "photo", contentType: "image/png"), "photo.png")
        XCTAssertEqual(HubServer.uploadName(header: nil, contentType: "image/jpeg; charset=x"), "attachment.jpeg")
    }
}
