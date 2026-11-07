import Foundation
import HomePadCore

/// Signing in to Spotify with Authorization Code and PKCE, the flow Spotify
/// recommends for mobile apps, which needs no client secret
/// (https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow).
/// The sign-in page and the callback are Core's `SpotifyPKCE`, since a member's
/// iPhone signs in too and hands its code to this HomePad. Everything here
/// builds requests and reads answers without side effects, so it is unit
/// tested. `SpotifyService` sends them.
enum SpotifyAuth {
    static let callbackScheme = SpotifyPKCE.callbackScheme
    static let redirectURI = SpotifyPKCE.redirectURI
    static let scopes = SpotifyPKCE.scopes
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    static func makeVerifier() -> String { SpotifyPKCE.makeVerifier() }
    static func challenge(for verifier: String) -> String { SpotifyPKCE.challenge(for: verifier) }

    static func authorizationURL(clientID: String, verifier: String, state: String) -> URL {
        SpotifyPKCE.authorizationURL(clientID: clientID, verifier: verifier, state: state)
    }

    /// The code from the callback, or why there is none.
    static func code(from callback: URL, state: String) throws -> String {
        do {
            return try SpotifyPKCE.code(from: callback, state: state)
        } catch {
            throw SpotifyError.signInFailed(error.localizedDescription)
        }
    }

    // MARK: Tokens

    /// The form for exchanging the code for tokens.
    static func tokenRequest(code: String, verifier: String, clientID: String) -> URLRequest {
        formRequest([
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI,
            "client_id": clientID, "code_verifier": verifier,
        ])
    }

    /// The form for a fresh access token.
    static func refreshRequest(refreshToken: String, clientID: String) -> URLRequest {
        formRequest(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }

    private static func formRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    /// Reads a token answer. A refresh answer may leave out the refresh token,
    /// and then the old one stays. Spotify's refresh tokens end six months after
    /// sign-in, and the token endpoint then answers `invalid_grant`.
    static func token(from data: Data, status: Int, previousRefreshToken: String?, now: Date = Date()) throws -> SpotifyToken {
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        guard (200..<300).contains(status) else {
            let code = json["error"]?.stringValue ?? "HTTP \(status)"
            if code == "invalid_grant" { throw SpotifyError.signInExpired }
            if code == "invalid_client" { throw SpotifyError.invalidClientID }
            throw SpotifyError.signInFailed(json["error_description"]?.stringValue ?? code)
        }
        guard let access = json["access_token"]?.stringValue,
              let refresh = json["refresh_token"]?.stringValue ?? previousRefreshToken else {
            throw SpotifyError.signInFailed("Spotify sent no token.")
        }
        let lifetime = json["expires_in"]?.doubleValue ?? 3600
        return SpotifyToken(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(lifetime))
    }
}

/// An access token and the refresh token that renews it.
struct SpotifyToken: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// True a minute before it runs out, so a request never meets an expired token.
    func needsRefresh(at now: Date = Date()) -> Bool {
        now >= expiresAt.addingTimeInterval(-60)
    }
}
