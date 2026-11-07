import Foundation
import HomePadCore

/// Why a Spotify request did not work, each with what to do about it.
enum SpotifyError: LocalizedError, Equatable {
    /// No client ID in Settings yet.
    case notSetUp
    /// Set up, but nobody signed in on this iPad.
    case signedOut
    case signInFailed(String)
    /// Spotify ends a sign-in six months after it was made.
    case signInExpired
    case invalidClientID
    /// Playback control needs Spotify Premium.
    case needsPremium
    /// A development app answers only accounts added under User Management.
    case notAllowed
    /// Nothing is playing Spotify anywhere, so there is nothing to control.
    case noActiveDevice
    /// New music should play on this iPad, and the Spotify app here is not open (`SpotifyWake`).
    case notOpenHere
    /// The Spotify app on this iPad is signed in to someone else, named here,
    /// and none of this account's own devices is on.
    case thisIPadIsOthers(String)
    case rateLimited
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Add your Spotify client ID in Settings, under Audio and AirPlay."
        case .signedOut: "Sign in to Spotify in Settings, under Audio and AirPlay."
        case .signInFailed(let reason): reason
        case .signInExpired: "Spotify signed HomePad out, as it does every six months. Sign in again in Settings."
        case .invalidClientID: "Spotify doesn't know that client ID. Check it in the Spotify developer dashboard."
        case .needsPremium: "Controlling playback from HomePad needs Spotify Premium."
        case .notAllowed: "This Spotify account isn't on your app's user list. Add it under User Management in the Spotify developer dashboard."
        case .noActiveDevice: "No Spotify device is on. Open Spotify on a speaker, a phone or this iPad, then try again."
        case .notOpenHere: "Spotify isn't open on this iPad. Open it, or end Guided Access so HomePad can, then try again."
        case .thisIPadIsOthers(let name):
            "Spotify on this iPad is signed in as \(name), so your music can't play here. Open Spotify on your phone, computer or speaker and pick it in Play On, or sign in to Spotify on this iPad as you."
        case .rateLimited: "Spotify asked HomePad to slow down. Try again in a minute."
        case .http(let status, let message): message ?? "Spotify answered with error \(status)."
        }
    }

    /// True when only signing in again fixes it.
    var needsSignIn: Bool {
        [.signedOut, .signInExpired, .invalidClientID, .notSetUp].contains(self)
    }
}

/// How HomePad sends a request to Spotify.
typealias SpotifyLoad = @Sendable (URLRequest) async throws -> (Data, URLResponse)

enum SpotifyLoader {
    static let network: SpotifyLoad = { try await URLSession.shared.data(for: $0) }
}

/// Spotify's Web API (https://api.spotify.com/v1), with a fresh access token on
/// every request. Requests and errors are built by static functions, so they are
/// unit tested without the network.
@MainActor
struct SpotifyClient {
    static let baseURL = URL(string: "https://api.spotify.com/v1")!

    /// A valid access token, refreshed when needed.
    let accessToken: @MainActor () async throws -> String
    /// Sends a request. `URLSession.shared` in the app, canned answers in tests and the demo.
    var load: SpotifyLoad = SpotifyLoader.network

    /// GET a JSON answer. A 204 (such as /me/player with nothing playing) reads as null.
    func get(_ path: String, query: [String: String] = [:]) async throws -> JSONValue {
        try await send("GET", path, query: query)
    }

    /// Sends a request and reads its JSON answer, if any.
    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:], body: JSONValue? = nil) async throws -> JSONValue {
        let request = Self.request(method, path, query: query, body: body, token: try await accessToken())
        let (data, response) = try await load(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.error(status: status, data: data) }
        guard status != 204, !data.isEmpty else { return .null }
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    }

    static func request(_ method: String, _ path: String, query: [String: String] = [:], body: JSONValue? = nil,
                        token: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.jsonString().utf8)
        } else if method == "PUT" || method == "POST" {
            // Spotify wants a length on bodiless PUT and POST requests.
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        return request
    }

    /// Reads Spotify's error object: `{"error": {"status", "message", "reason"}}`.
    static func error(status: Int, data: Data) -> SpotifyError {
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        let message = json["error"]?["message"]?.stringValue ?? json["error"]?.stringValue
        let reason = json["error"]?["reason"]?.stringValue
        switch status {
        case 401:
            return .signedOut
        case 403:
            if reason == "PREMIUM_REQUIRED" || message?.localizedCaseInsensitiveContains("premium") == true { return .needsPremium }
            if message?.localizedCaseInsensitiveContains("not registered") == true { return .notAllowed }
            return .http(status, message)
        case 404 where reason == "NO_ACTIVE_DEVICE" || message?.localizedCaseInsensitiveContains("no active device") == true:
            return .noActiveDevice
        case 429:
            return .rateLimited
        default:
            return .http(status, message)
        }
    }
}
