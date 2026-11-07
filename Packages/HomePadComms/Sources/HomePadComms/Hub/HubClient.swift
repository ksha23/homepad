import CommsKit
import Foundation

/// Talks to one member's hub. It holds no message data.
public struct HubClient: Sendable {
    public enum Failure: Error, LocalizedError, Equatable {
        case unauthorized
        case unreachable(String)
        case server(Int)
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .tooLarge: "That file is over the 100 MB limit."
            case .unauthorized: "The hub rejected the token."
            case .unreachable(let detail): "Cannot reach the hub: \(detail)"
            case .server(let code): "The hub answered with status \(code)."
            }
        }
    }

    let credentials: HubCredentials
    let session: URLSession

    public init(credentials: HubCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func status() async throws -> HubStatus {
        try await get(CommsRoutes.status)
    }

    public func conversations(limit: Int = 50) async throws -> [CommsConversation] {
        try await get(CommsRoutes.conversations, query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    public func messages(in conversationID: String, before: Date? = nil, limit: Int = 50) async throws -> [CommsMessage] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { query.append(URLQueryItem(name: "before", value: ISO8601DateFormatter().string(from: before))) }
        return try await get(CommsRoutes.messages(in: conversationID), query: query)
    }

    public func send(_ text: String, to conversationID: String) async throws {
        let body = try CommsRoutes.makeEncoder().encode(SendMessageRequest(text: text))
        _ = try await perform(request(CommsRoutes.messages(in: conversationID), method: "POST", body: body))
    }

    public func markRead(_ conversationID: String) async throws {
        _ = try await perform(request(CommsRoutes.read(conversationID), method: "POST"))
    }

    /// Live events, resuming after `lastID` when given. The stream ends when the connection
    /// drops, and fails after 45 seconds of silence (the hub pings every 15).
    public func events(after lastID: Int? = nil) -> AsyncThrowingStream<StreamPacket, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var events = try request(CommsRoutes.events)
                    events.timeoutInterval = 45
                    if let lastID { events.setValue(String(lastID), forHTTPHeaderField: "Last-Event-ID") }
                    let (bytes, response) = try await session.bytes(for: events)
                    try Self.check(response)
                    var parser = StreamParser()
                    for try await line in bytes.lines {
                        if let packet = parser.feed(line) { continuation.yield(packet) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.wrap(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await perform(request(path, query: query))
        return try CommsRoutes.makeDecoder().decode(T.self, from: data)
    }

    func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        var components = URLComponents(url: credentials.baseURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw Failure.unreachable("bad address") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 15
        return request
    }

    func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Self.check(response)
            return data
        } catch {
            throw Self.wrap(error)
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw Failure.unauthorized
        default: throw Failure.server(http.statusCode)
        }
    }

    static func wrap(_ error: Error) -> Error {
        if error is Failure || error is CancellationError { return error }
        guard let urlError = error as? URLError else { return Failure.unreachable(error.localizedDescription) }
        return Failure.unreachable("\(urlError.localizedDescription) (\(urlError.code.rawValue)). \(hint(for: urlError.code))")
    }

    /// What most likely went wrong, in words a person can act on.
    private static func hint(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed:
            "If Wi-Fi is on, allow HomePad under Settings > Privacy & Security > Local Network."
        case .cannotConnectToHost, .timedOut, .cannotFindHost:
            "Check that the Mac is awake, the hub is running, and the iPad is on the same network."
        case .appTransportSecurityRequiresSecureConnection:
            "iOS blocks plain http to this address. Use a local address or an https address."
        default:
            "Check the hub address."
        }
    }
}

extension HubClient {
    /// An attachment's bytes. With `thumbnail` the hub sends a small cached JPEG of a photo.
    public func attachment(_ id: String, thumbnail: Bool = false) async throws -> Data {
        let query = thumbnail ? [URLQueryItem(name: "size", value: "thumb")] : []
        return try await perform(request(CommsRoutes.attachment(id), query: query))
    }

    /// The address and headers AVPlayer needs to stream a video attachment with seeking.
    public func attachmentStream(_ id: String) -> (url: URL, headers: [String: String])? {
        guard let url = try? request(CommsRoutes.attachment(id)).url else { return nil }
        return (url, ["Authorization": "Bearer \(credentials.token)"])
    }
}

extension HubClient {
    /// The Contacts picture for a phone number or email. Throws when the contact has none.
    public func contactPhoto(handle: String) async throws -> Data {
        try await perform(request("/v1/contacts/photo", query: [URLQueryItem(name: "handle", value: handle)]))
    }
}
