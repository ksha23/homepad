import CommsKit
import XCTest
@testable import HomePadComms
import HomePadCore

final class CommsCacheTests: XCTestCase {
    private func makeCache() -> (CommsCache, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("comms-cache-\(UUID().uuidString)")
        return (CommsCache(directory: directory, keychain: MemorySecrets()), directory)
    }

    private func snapshot() -> CacheSnapshot {
        let message = CommsMessage(id: "m1", conversationID: "c1", sender: "+1", text: "a secret", date: Date(timeIntervalSince1970: 1_700_000_000), isFromMe: false, isRead: true)
        let conversation = CommsConversation(id: "c1", title: "Sam", participants: ["+1"], isGroup: false, service: .iMessage, lastMessagePreview: "a secret", lastMessageDate: message.date, unreadCount: 0)
        return CacheSnapshot(conversations: [conversation], threads: ["c1": [message]], lastEventID: 7, savedAt: message.date)
    }

    func testRoundTrip() {
        let (cache, _) = makeCache()
        let member = UUID()
        XCTAssertTrue(cache.save(snapshot(), member: member))
        XCTAssertEqual(cache.load(member: member), snapshot())
    }

    func testFileOnDiskDoesNotContainTheText() throws {
        let (cache, directory) = makeCache()
        let member = UUID()
        cache.save(snapshot(), member: member)
        let bytes = try Data(contentsOf: directory.appendingPathComponent("\(member.uuidString).cache"))
        XCTAssertNil(bytes.range(of: Data("a secret".utf8)), "messages must not be stored in plain text")
    }

    func testAnotherMemberCannotReadIt() {
        let (cache, directory) = makeCache()
        let owner = UUID(), other = UUID()
        cache.save(snapshot(), member: owner)
        try? FileManager.default.copyItem(at: directory.appendingPathComponent("\(owner.uuidString).cache"), to: directory.appendingPathComponent("\(other.uuidString).cache"))
        XCTAssertNil(cache.load(member: other), "a copied file is useless without its owner's key")
    }

    func testDeleteRemovesFileAndKey() {
        let (cache, directory) = makeCache()
        let member = UUID()
        cache.save(snapshot(), member: member)
        cache.delete(member: member)
        XCTAssertNil(cache.load(member: member))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(member.uuidString).cache").path))
    }

    func testTrimKeepsRecentMessagesOnly() {
        let (cache, _) = makeCache()
        let member = UUID()
        var big = snapshot()
        big.threads["c1"] = (0..<100).map { CommsMessage(id: "m\($0)", conversationID: "c1", sender: nil, text: "t", date: Date(timeIntervalSince1970: Double($0)), isFromMe: true, isRead: true) }
        cache.save(big, member: member)
        XCTAssertEqual(cache.load(member: member)?.threads["c1"]?.count, CommsCache.maxMessagesPerThread)
        XCTAssertEqual(cache.load(member: member)?.threads["c1"]?.last?.id, "m99")
    }
}
