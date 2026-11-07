import CommsKit
import XCTest
@testable import HomePadComms

@MainActor
final class CommsStoreTests: XCTestCase {
    private func message(_ id: String, from me: Bool, read: Bool = false, in chat: String = "c1") -> CommsMessage {
        CommsMessage(id: id, conversationID: chat, sender: me ? nil : "+1", text: "t\(id)", date: Date(), isFromMe: me, isRead: read)
    }

    func testIncomingMessageRaisesUnreadAndBanner() {
        let store = CommsStore()
        store.apply(.message(message("1", from: false)))
        XCTAssertEqual(store.banner?.id, "1")
    }

    func testLockWipesEverything() {
        let store = CommsStore()
        store.apply(.message(message("1", from: false)))
        store.lock()
        XCTAssertNil(store.banner)
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertEqual(store.phase, .locked)
    }

    func testReadEventClearsBanner() {
        let store = CommsStore()
        store.apply(.message(message("1", from: false)))
        store.apply(.read(conversationID: "c1", unreadCount: 0))
        XCTAssertNil(store.banner)
    }

    func testOwnMessageRaisesNoBanner() {
        let store = CommsStore()
        store.apply(.message(message("1", from: true)))
        XCTAssertNil(store.banner)
    }

    func testOpenConversationRaisesNoBanner() {
        let store = CommsStore()
        store.openConversationID = "c1"
        store.apply(.message(message("1", from: false)))
        XCTAssertNil(store.banner)
    }

    func testReplayedEventAndRepeatedMessageRaiseNoSecondBanner() {
        let store = CommsStore()
        store.handle(.event(id: 5, .message(message("1", from: false))))
        XCTAssertEqual(store.banner?.id, "1")
        store.dismissBanner()
        // The same event again, as a reconnect replays it, and an older id.
        store.handle(.event(id: 5, .message(message("1", from: false))))
        store.handle(.event(id: 4, .message(message("2", from: false))))
        XCTAssertNil(store.banner)
        // The same message under a new id (after a new hub run) is still the same message.
        store.handle(.hello(epoch: 9))
        store.handle(.event(id: 1, .message(message("1", from: false))))
        XCTAssertNil(store.banner)
    }

    func testOldMessageRaisesNoBanner() {
        let store = CommsStore()
        let old = CommsMessage(id: "9", conversationID: "c1", sender: "+1", text: "t", date: Date(timeIntervalSinceNow: -3600), isFromMe: false, isRead: false)
        store.apply(.message(old))
        XCTAssertNil(store.banner)
    }

    func testNoCredentialsMeansNotConfigured() {
        let store = CommsStore()
        store.connect(nil)
        XCTAssertEqual(store.phase, .notConfigured)
    }
}

@MainActor
final class CommsConnectionTests: XCTestCase {
    func testStoreKeepsConnectingStateUntilTheHubAnswers() async {
        let store = CommsStore(makeClient: { HubClient(credentials: $0) })
        store.connect(HubCredentials(baseURL: URL(string: "http://127.0.0.1:9")!, token: "x"))
        XCTAssertEqual(store.phase, .connecting)
        store.lock()
        XCTAssertEqual(store.phase, .locked)
    }
}
