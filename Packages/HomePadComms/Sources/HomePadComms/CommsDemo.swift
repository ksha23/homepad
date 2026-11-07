#if DEBUG
import CommsKit
import Foundation

/// Made-up conversations for screenshots and UI checks. A stand-in hub inside the app answers the
/// hub's own routes (`CommsDemoHub`), so the whole Messages app runs as it does against a Mac.
/// Nothing reaches a real hub and nothing is saved to the Keychain. Debug builds only.
///
///     -HomePadCommsDemo YES               use the stand-in hub for whoever is at the iPad
///     -HomePadMessagesOpen demo.sam       open this conversation in Messages
enum CommsDemo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "HomePadCommsDemo") }

    /// The conversation Messages opens on, from `-HomePadMessagesOpen`.
    static var openConversationID: String? { UserDefaults.standard.string(forKey: "HomePadMessagesOpen") }

    static let host = "demo.homepad.invalid"
    static let credentials = HubCredentials(baseURL: URL(string: "https://\(host)")!, token: "demo")

    /// Starts answering the hub's routes. Call once, before the store connects.
    static func start() {
        URLProtocol.registerClass(CommsDemoHub.self)
    }

    /// A conversation and its messages, newest last, each as minutes before now.
    private struct Thread {
        var conversation: CommsConversation
        var messages: [(minutesAgo: Double, from: String?, text: String)]
    }

    private static func threads(now: Date = Date()) -> [Thread] {
        func conversation(_ id: String, _ title: String, _ handles: [String], isGroup: Bool = false,
                          service: CommsService = .iMessage, unread: Int = 0) -> CommsConversation {
            CommsConversation(id: id, title: title, participants: handles, isGroup: isGroup, service: service,
                              lastMessagePreview: "", lastMessageDate: now, unreadCount: unread)
        }
        return [
            // Read, since a conversation open on screen is, and the demo hub sends no read events.
            Thread(conversation: conversation("demo.sam", "Sam", ["+15555550101"]), messages: [
                (95, nil, "Are you still at the office?"),
                (93, "Sam", "Leaving in 20. Traffic looks fine"),
                (60, nil, "Can you pick up the cake for Saturday? The bakery closes at 6"),
                (58, "Sam", "On it 🎂"),
                (31, "Sam", "They had chocolate or lemon. I went with lemon"),
                (30, nil, "Perfect, Maya loves lemon"),
                (12, "Sam", "Also grabbing oat milk. Anything else?"),
                (4, "Sam", "Home in 15"),
            ]),
            Thread(conversation: conversation("demo.family", "Family", ["+15555550101", "+15555550102", "+15555550103"],
                                              isGroup: true, unread: 2), messages: [
                (180, "Mom", "Dinner at ours on Sunday? 6:30"),
                (170, nil, "We'll be there!"),
                (26, "Maya", "Can I bring the puzzle?"),
                (20, "Mom", "Of course 🧩"),
            ]),
            Thread(conversation: conversation("demo.jordan", "Jordan Lee", ["jordan@example.com"]), messages: [
                (300, "Jordan Lee", "Tickets are booked for Friday"),
                (290, nil, "Amazing, see you at the game!"),
            ]),
            Thread(conversation: conversation("demo.bookclub", "Book Club", ["+15555550104", "+15555550105"], isGroup: true),
                   messages: [
                (1500, "Priya", "We're doing chapters 10 to 12 for next week"),
                (1440, "Chris", "Thursday still works for me"),
            ]),
            Thread(conversation: conversation("demo.dentist", "Riverside Dental", ["+15555550199"], service: .sms), messages: [
                (2900, "Riverside Dental", "Reminder: your cleaning is Thursday at 10:30 AM. Reply C to confirm."),
                (2880, nil, "C"),
            ]),
            Thread(conversation: conversation("demo.priya", "Priya", ["+15555550104"]), messages: [
                (4400, "Priya", "Sent you the photos from the hike"),
                (4380, nil, "These are great, thank you!"),
            ]),
        ].map { thread in
            var thread = thread
            if let last = thread.messages.last {
                thread.conversation.lastMessagePreview = last.text
                thread.conversation.lastMessageDate = now.addingTimeInterval(-last.minutesAgo * 60)
            }
            return thread
        }
    }

    /// The messages of one conversation, newest first as the hub sends them. The newest `unreadCount` are unread.
    private static func messages(of thread: Thread, now: Date = Date()) -> [CommsMessage] {
        let id = thread.conversation.id
        let firstUnread = thread.messages.count - thread.conversation.unreadCount
        return thread.messages.enumerated().reversed().map { index, message in
            // Each person gets a made-up handle of their own, so a group's bubbles are grouped by sender.
            CommsMessage(id: "\(id).\(index)", conversationID: id,
                         sender: message.from.map { "\($0.lowercased().replacingOccurrences(of: " ", with: "."))@example.com" },
                         senderName: message.from, text: message.text,
                         date: now.addingTimeInterval(-message.minutesAgo * 60),
                         isFromMe: message.from == nil, isRead: index < firstUnread)
        }
    }

    /// The answer to one request, or nil for the event stream, which stays open without events.
    static func response(path: String, method: String) -> (status: Int, body: Data)? {
        let encoder = CommsRoutes.makeEncoder()
        let threads = threads()
        func json(_ value: some Encodable) -> (status: Int, body: Data) { (200, (try? encoder.encode(value)) ?? Data()) }
        switch path {
        case CommsRoutes.status:
            return json(HubStatus(version: "demo", account: nil, canReadMessages: true, canSendMessages: true))
        case CommsRoutes.conversations:
            return json(threads.map(\.conversation).sorted { $0.lastMessageDate > $1.lastMessageDate })
        case CommsRoutes.events:
            return nil
        default:
            if method == "GET", let thread = threads.first(where: { CommsRoutes.messages(in: $0.conversation.id) == path }) {
                return json(messages(of: thread))
            }
            // Sending and marking read are accepted. Contact photos and attachments are not there.
            return method == "POST" ? (202, Data()) : (404, Data())
        }
    }
}

/// Answers requests to the demo hub's host with `CommsDemo.response(path:method:)`.
final class CommsDemoHub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == CommsDemo.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return }
        let answer = CommsDemo.response(path: path, method: request.httpMethod ?? "GET")
        let type = answer == nil ? "text/event-stream" : "application/json"
        guard let response = HTTPURLResponse(url: url, statusCode: answer?.status ?? 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": type]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // The event stream stays open, as the hub's does between events.
        guard let answer else { return }
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
