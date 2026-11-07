import CommsKit
import XCTest
@testable import HomePadComms

final class StreamParserTests: XCTestCase {
    private func feed(_ lines: [String]) -> [StreamPacket] {
        var parser = StreamParser()
        return lines.compactMap { parser.feed($0) }
    }

    func testNumberedEventCarriesItsID() {
        let json = #"{"type":"read","conversationID":"c","unreadCount":2}"#
        XCTAssertEqual(feed(["id: 7", "data: \(json)"]), [.event(id: 7, .read(conversationID: "c", unreadCount: 2))])
    }

    func testHelloAndGapAreRecognized() {
        XCTAssertEqual(feed(["event: hello", #"data: {"epoch":1700}"#]), [.hello(epoch: 1700)])
        XCTAssertEqual(feed(["event: gap", "data: {}"]), [.gap])
    }

    func testHeartbeatsAndUnknownLinesAreIgnored() {
        XCTAssertEqual(feed([": ping", "retry: 1000"]), [])
    }

    func testIDDoesNotLeakIntoTheNextEvent() {
        let json = #"{"type":"read","conversationID":"c","unreadCount":0}"#
        let packets = feed(["id: 3", "data: \(json)", "data: \(json)"])
        XCTAssertEqual(packets.last, .event(id: nil, .read(conversationID: "c", unreadCount: 0)))
    }
}

@MainActor
final class CacheRestoreTests: XCTestCase {
    private func store(with snapshot: CacheSnapshot, member: UUID) -> CommsStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("comms-restore-\(UUID().uuidString)")
        let cache = CommsCache(directory: directory, keychain: MemorySecrets())
        cache.save(snapshot, member: member)
        return CommsStore(makeClient: { HubClient(credentials: $0) }, cache: cache)
    }

    private func snapshot() -> CacheSnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let conversation = CommsConversation(id: "c1", title: "Sam", participants: [], isGroup: false, service: .iMessage, lastMessagePreview: "hi", lastMessageDate: date, unreadCount: 1)
        return CacheSnapshot(conversations: [conversation], threads: [:], lastEventID: 4, hubEpoch: 9, savedAt: date)
    }

    func testSavedMessagesAppearBeforeTheHubAnswers() {
        let member = UUID()
        let store = store(with: snapshot(), member: member)
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"), member: member)
        XCTAssertEqual(store.conversations.map(\.id), ["c1"], "the cache fills the list at once")
        XCTAssertTrue(store.isReconnecting, "and the strip says the Mac has not answered yet")
        store.lock()
    }

    func testUnreadTotalSumsAcrossConversations() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func chat(_ id: String, unread: Int) -> CommsConversation {
            CommsConversation(id: id, title: id, participants: [], isGroup: false, service: .iMessage, lastMessagePreview: "", lastMessageDate: date, unreadCount: unread)
        }
        let member = UUID()
        let saved = CacheSnapshot(conversations: [chat("a", unread: 2), chat("b", unread: 0), chat("c", unread: 3)], threads: [:], lastEventID: 1, hubEpoch: 1, savedAt: date)
        let store = store(with: saved, member: member)
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"), member: member)
        XCTAssertEqual(store.unreadTotal, 5)
        store.lock()
        XCTAssertEqual(store.unreadTotal, 0, "a locked store counts nothing, so the icon badge goes away")
    }

    func testLockClearsMemoryButKeepsTheFile() {
        let member = UUID()
        let store = store(with: snapshot(), member: member)
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"), member: member)
        store.lock()
        XCTAssertTrue(store.conversations.isEmpty)
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"), member: member)
        XCTAssertEqual(store.conversations.count, 1, "the encrypted copy survives a lock")
        store.lock()
    }

    func testAnotherMemberDoesNotGetTheCache() {
        let owner = UUID()
        let store = store(with: snapshot(), member: owner)
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"), member: UUID())
        XCTAssertTrue(store.conversations.isEmpty)
        store.lock()
    }

    func testForgetRemovesTheCopy() {
        let member = UUID()
        let store = store(with: snapshot(), member: member)
        store.forgetSavedMessages(for: member)
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"), member: member)
        XCTAssertTrue(store.conversations.isEmpty)
        store.lock()
    }
}
