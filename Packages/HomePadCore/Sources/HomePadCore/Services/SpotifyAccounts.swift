import CryptoKit
import Foundation

/// Signing in to Spotify with Authorization Code and PKCE, which needs no
/// client secret (https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow).
///
/// It is in Core because two devices use it. The HomePad signs in on the iPad
/// and exchanges codes (the Audio module), and a member's iPhone signs in on
/// the phone and hands its code to the HomePad (the Connect module). Both use
/// the household's one developer app, so the redirect URI and scopes match.
public enum SpotifyPKCE {
    /// The redirect URI to register in the Spotify developer dashboard. Spotify
    /// asks iOS apps for a lowercase scheme used only for its login, with a path
    /// (https://developer.spotify.com/documentation/web-api/concepts/apps).
    /// `ASWebAuthenticationSession` catches it, so Info.plist needs no entry.
    public static let callbackScheme = "homepad-spotify-login"
    public static let redirectURI = "\(callbackScheme)://callback"

    /// Playback control and reading the library. Nothing that changes the library.
    public static let scopes = [
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
        "playlist-read-private", "playlist-read-collaborative", "user-library-read",
        "user-read-recently-played", "user-follow-read",
    ]

    public static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!

    /// Why a callback carries no code.
    public enum Failure: LocalizedError, Equatable, Sendable {
        case canceled
        case spotifySaid(String)
        case notThisSignIn
        case noCode

        public var errorDescription: String? {
            switch self {
            case .canceled: "Spotify sign-in was canceled."
            case .spotifySaid(let error): "Spotify said \(error)."
            case .notThisSignIn: "Spotify's answer did not match this sign-in."
            case .noCode: "Spotify sent no sign-in code."
            }
        }
    }

    /// A random code verifier: 64 characters from the unreserved set (RFC 7636 allows 43 to 128).
    public static func makeVerifier() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// The S256 challenge: the verifier's SHA-256, base64url without padding.
    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The page the person signs in on. `showDialog` makes Spotify ask which
    /// account even when the browser is already signed in, which a person's
    /// own iPhone needs when Safari holds someone else's Spotify.
    public static func authorizationURL(clientID: String, verifier: String, state: String, showDialog: Bool = false) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        if showDialog { items.append(URLQueryItem(name: "show_dialog", value: "true")) }
        components.queryItems = items
        return components.url!
    }

    /// The code from the callback, or why there is none.
    public static func code(from callback: URL, state: String) throws(Failure) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw error == "access_denied" ? .canceled : .spotifySaid(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else { throw .notThisSignIn }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw .noCode }
        return code
    }
}

/// One member's Spotify on a HomePad, as their own iPhone sees it.
public struct SpotifyMemberAccount: Codable, Equatable, Sendable {
    /// Spotify is turned on there and has the household's client ID.
    public var isSetUp: Bool
    /// The household's developer app, so the phone signs in to the same one.
    /// Not a secret: PKCE needs none.
    public var clientID: String?
    /// The member's signed-in Spotify account, by its display name.
    public var accountName: String?
    /// A refresh token for the member is kept on that HomePad.
    public var isSignedIn: Bool
    /// The member had signed in, and Spotify ended it (six months, or a new client ID).
    public var needsSignInAgain: Bool
    /// What went wrong last, in words.
    public var problem: String?

    public init(isSetUp: Bool, clientID: String? = nil, accountName: String? = nil, isSignedIn: Bool = false,
                needsSignInAgain: Bool = false, problem: String? = nil) {
        self.isSetUp = isSetUp
        self.clientID = clientID
        self.accountName = accountName
        self.isSignedIn = isSignedIn
        self.needsSignInAgain = needsSignInAgain
        self.problem = problem
    }
}

/// Each household member's own Spotify account on a HomePad, for the sign-in
/// on their own iPhone. The Audio module's media service adopts it. Callers
/// check `services.media as? any SpotifyMemberAccounts`, as `MediaSeeking` is.
@MainActor
public protocol SpotifyMemberAccounts: AnyObject {
    /// Where the member's Spotify stands on this HomePad.
    func spotifyAccount(for member: UUID) -> SpotifyMemberAccount
    /// Exchanges a sign-in code made on the member's own iPhone for their
    /// tokens, and keeps them on this HomePad for that member only.
    /// `deviceName` says where they signed in, for Settings.
    func linkSpotify(code: String, verifier: String, for member: UUID, from deviceName: String) async throws -> SpotifyMemberAccount
    /// Forgets the member's Spotify sign-in on this HomePad.
    func signOutSpotify(for member: UUID)
}
