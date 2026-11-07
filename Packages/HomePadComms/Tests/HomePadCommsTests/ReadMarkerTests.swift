import CommsKit
import XCTest
@testable import HomePadComms

private let start = Date(timeIntervalSince1970: 1_700_000_000)

/// A message in conversation `c1`, `minute` minutes after `start`.
private func message(_ id: String, at minute: Double, fromMe: Bool = false, read: Bool = false) -> CommsMessage {
    CommsMessage(id: id, conversationID: "c1", sender: fromMe ? nil : "+15555550101", text: id,
                 date: start.addingTimeInterval(minute * 60), isFromMe: fromMe, isRead: read || fromMe)
}

private func at(_ minute: Double) -> Date { start.addingTimeInterval(minute * 60) }

/// The rules, without a store.
final class ReadMarkerRuleTests: XCTestCase {
    func testNoMarkerShowsTheHubCount() {
        XCTAssertEqual(ReadMarkers().unreadCount("c1", hubCount: 3, newest: at(3), thread: nil), 3)
    }

    func testTheHubSayingReadWins() {
        var markers = ReadMarkers()
        markers.markSeen("c1", through: at(1))
        XCTAssertEqual(markers.unreadCount("c1", hubCount: 0, newest: at(5), thread: nil), 0, "read on the iPhone or the Mac")
    }

    func testNothingNewerThanTheMarkerIsRead() {
        var markers = ReadMarkers()
        markers.markSeen("c1", through: at(3))
        XCTAssertEqual(markers.unreadCount("c1", hubCount: 3, newest: at(3), thread: nil), 0, "the locked Mac still counts 3")
    }

    func testOnlyUnreadMessagesFromOthersAfterTheMarkerCount() {
        var markers = ReadMarkers()
        markers.markSeen("c1", through: at(3))
        let thread = [
            message("old1", at: 1), message("old2", at: 2), message("old3", at: 3),
            message("new", at: 4), message("mine", at: 5, fromMe: true), message("readElsewhere", at: 6, read: true),
            message("newer", at: 7),
        ]
        XCTAssertEqual(markers.unreadCount("c1", hubCount: 5, newest: at(7), thread: thread), 2, "not the Mac's 5")
        XCTAssertEqual(markers.unreadCount("c1", hubCount: 1, newest: at(7), thread: thread), 1, "never more than the hub says")
    }

    func testAThreadThatDoesNotReachTheMarkerShowsTheHubCount() {
        var markers = ReadMarkers()
        markers.markSeen("c1", through: at(1))
        let thread = [message("a", at: 5), message("b", at: 6)]
        XCTAssertEqual(markers.unreadCount("c1", hubCount: 9, newest: at(6), thread: thread), 9)
    }

    func testAMarkerNeverMovesBack() {
        var markers = ReadMarkers()
        markers.markSeen("c1", through: at(5))
        markers.markSeen("c1", through: at(2))
        XCTAssertEqual(markers.marker(for: "c1"), at(5))
    }

    func testTrimKeepsTheNewestMarkers() {
        var markers = ReadMarkers()
        for index in 0..<(ReadMarkers.limit + 10) { markers.markSeen("c\(index)", through: at(Double(index))) }
        let trimmed = markers.trimmed()
        XCTAssertEqual(trimmed.seen.count, ReadMarkers.limit)
        XCTAssertNil(trimmed.marker(for: "c0"))
        XCTAssertNotNil(trimmed.marker(for: "c\(ReadMarkers.limit + 9)"))
    }
}

/// The rules through the store: the list, the icon badge total and the banner agree.
@MainActor
final class ReadStateTests: XCTestCase {
    private let offline = HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x")

    private func makeCache() -> CommsCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("comms-read-\(UUID().uuidString)")
        return CommsCache(directory: directory, keychain: MemorySecrets())
    }

    /// A store showing conversation `c1`, three messages long, all unread on a Mac that never marks them read.
    private func connectedStore(cache: CommsCache, member: UUID) -> CommsStore {
        let thread = [message("m1", at: 1), message("m2", at: 2), message("m3", at: 3)]
        let conversation = CommsConversation(id: "c1", title: "Sam", participants: ["+15555550101"], isGroup: false, service: .iMessage,
                                             lastMessagePreview: "m3", lastMessageDate: at(3), unreadCount: 3)
        cache.save(CacheSnapshot(conversations: [conversation], threads: ["c1": thread], lastEventID: 1, hubEpoch: 1, savedAt: start), member: member)
        let store = CommsStore(makeClient: { HubClient(credentials: $0) }, cache: cache)
        store.connect(offline, member: member)
        return store
    }

    func testOpeningClearsTheDotAtOnceAndTheMacCannotBringItBack() {
        let store = connectedStore(cache: makeCache(), member: UUID())
        XCTAssertEqual(store.unreadTotal, 3)
        store.markSeen("c1")
        XCTAssertEqual(store.conversations.first?.unreadCount, 0)
        XCTAssertEqual(store.unreadTotal, 0, "the icon badge and the Control Center tile follow")
        store.apply(.read(conversationID: "c1", unreadCount: 3))
        XCTAssertEqual(store.unreadTotal, 0, "the locked Mac still counts 3")
        store.lock()
    }

    func testANewMessageCountsOnlyItself() {
        let store = connectedStore(cache: makeCache(), member: UUID())
        store.markSeen("c1")
        store.apply(.message(message("m4", at: 4)))
        store.apply(.read(conversationID: "c1", unreadCount: 4))
        XCTAssertEqual(store.conversations.first?.unreadCount, 1, "not the Mac's 4")
        XCTAssertEqual(store.unreadTotal, 1)
        store.lock()
    }

    func testReplyingFromAnotherDeviceCountsAsRead() {
        let store = connectedStore(cache: makeCache(), member: UUID())
        store.markSeen("c1")
        store.apply(.message(message("m4", at: 4)))
        store.apply(.message(message("reply", at: 5, fromMe: true)))
        store.apply(.read(conversationID: "c1", unreadCount: 4))
        XCTAssertEqual(store.unreadTotal, 0)
        store.lock()
    }

    func testTheConversationOnScreenStaysRead() {
        let store = connectedStore(cache: makeCache(), member: UUID())
        store.openConversationID = "c1"
        store.markSeen("c1")
        store.apply(.message(message("m4", at: 4)))
        store.apply(.read(conversationID: "c1", unreadCount: 4))
        XCTAssertEqual(store.unreadTotal, 0)
        store.lock()
    }

    func testWhatWasReadIsRememberedAfterALock() async throws {
        let cache = makeCache()
        let member = UUID()
        let store = connectedStore(cache: cache, member: member)
        store.markSeen("c1")
        store.lock()
        // The lock saves in the background.
        var saved: Date?
        for _ in 0..<100 {
            saved = cache.load(member: member)?.readMarkers?.marker(for: "c1")
            if saved != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(saved, at(3))
        store.connect(offline, member: member)
        store.apply(.read(conversationID: "c1", unreadCount: 3))
        XCTAssertEqual(store.unreadTotal, 0, "the Mac's count does not bring the dot back")
        store.lock()
    }
}
