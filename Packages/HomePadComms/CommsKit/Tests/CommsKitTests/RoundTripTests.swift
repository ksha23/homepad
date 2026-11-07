import XCTest
@testable import CommsKit

final class RoundTripTests: XCTestCase {
    func testEventRoundTrip() throws {
        let message = CommsMessage(id: "g", conversationID: "iMessage;-;+1", sender: "+1", text: "hi", date: Date(timeIntervalSince1970: 1_700_000_000), isFromMe: false, isRead: false)
        let events: [CommsEvent] = [.message(message), .read(conversationID: "c", unreadCount: 2)]
        let data = try CommsRoutes.makeEncoder().encode(events)
        XCTAssertEqual(try CommsRoutes.makeDecoder().decode([CommsEvent].self, from: data), events)
    }

    func testMessageDecodesWithAndWithoutReactions() throws {
        let reaction = CommsReaction(kind: "love", sender: "+2", isFromMe: false)
        let message = CommsMessage(id: "g", conversationID: "c", sender: "+1", text: "hi", date: Date(timeIntervalSince1970: 1_700_000_000), isFromMe: false, isRead: true, reactions: [reaction])
        let encoder = CommsRoutes.makeEncoder()
        let decoder = CommsRoutes.makeDecoder()
        XCTAssertEqual(try decoder.decode(CommsMessage.self, from: encoder.encode(message)), message)

        // An old hub or cache wrote no `reactions` key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(message)) as? [String: Any])
        json["reactions"] = nil
        let old = try decoder.decode(CommsMessage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.reactions, [])
        XCTAssertEqual(old.text, "hi")
    }

    func testPathEncodingKeepsSemicolonsOutOfTheRoute() {
        XCTAssertEqual(CommsRoutes.messages(in: "iMessage;-;+1"), "/v1/conversations/iMessage%3B-%3B+1/messages")
    }
}

final class UploadRuleTests: XCTestCase {
    func testAttachmentRoute() {
        XCTAssertEqual(CommsRoutes.sendAttachment(in: "iMessage;-;+1"), "/v1/conversations/iMessage%3B-%3B+1/attachments")
    }

    func testFilenameSanitizing() {
        XCTAssertEqual(CommsUpload.sanitizedFilename("../../etc/passwd"), "_.._etc_passwd")
        XCTAssertEqual(CommsUpload.sanitizedFilename("IMG_0001.HEIC"), "IMG_0001.HEIC")
        XCTAssertEqual(CommsUpload.sanitizedFilename(".hidden.jpg"), "hidden.jpg")
        XCTAssertEqual(CommsUpload.sanitizedFilename("a\nb.png"), "a_b.png")
        XCTAssertEqual(CommsUpload.sanitizedFilename(nil), "attachment")
        XCTAssertEqual(CommsUpload.sanitizedFilename("  "), "attachment")
        let long = CommsUpload.sanitizedFilename(String(repeating: "x", count: 300) + ".jpg")
        XCTAssertEqual(long.count, 120)
        XCTAssertTrue(long.hasSuffix(".jpg"))
    }

    func testSizeCap() {
        XCTAssertFalse(CommsUpload.allows(0))
        XCTAssertTrue(CommsUpload.allows(CommsUpload.maxBytes))
        XCTAssertFalse(CommsUpload.allows(CommsUpload.maxBytes + 1))
    }
}

final class WireShapeTests: XCTestCase {
    func testEventIsFlatWithTypeField() throws {
        let data = try CommsRoutes.makeEncoder().encode(CommsEvent.read(conversationID: "c", unreadCount: 3))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "read")
        XCTAssertEqual(json["unreadCount"] as? Int, 3)
    }
}
