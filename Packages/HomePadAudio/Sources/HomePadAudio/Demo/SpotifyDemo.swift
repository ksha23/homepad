#if DEBUG
import Foundation
import HomePadCore

/// Made-up Spotify accounts for simulator screenshots, which cannot sign in:
/// `-HomePadSpotifyDemoAccounts YES`, debug builds only, with
/// `-HomePadDemoContent YES` for the people. It turns Spotify on with a
/// made-up client ID. The household and Sam are signed in, Jordan's sign-in
/// ended, and Alex has none. Tokens stay in memory, and every request is
/// answered here, so nothing reaches Spotify or the Keychain.
enum SpotifyDemo {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "HomePadSpotifyDemoAccounts") }

    static let clientID = "0123456789abcdef0123456789abcdef"

    /// The token endpoint answers with a token, everything else with nothing (204).
    static let load: SpotifyLoad = { request in
        let isToken = request.url?.host() == "accounts.spotify.com"
        let body = isToken ? Data(#"{"access_token":"demo","token_type":"Bearer","expires_in":3600}"#.utf8) : Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: isToken ? 200 : 204, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    /// Refresh tokens in memory.
    final class Secrets: SpotifySecrets {
        private var values: [String: String] = [:]
        func string(for account: String) -> String? { values[account] }
        @discardableResult func set(_ value: String?, for account: String) -> Bool {
            values[account] = value
            return true
        }
    }

    @MainActor private static var isSeeded = false

    /// Links the demo accounts once per launch, once the demo people are in the household.
    @MainActor
    static func seed(_ spotify: SpotifyService, members: [HouseholdMember]) {
        guard isEnabled, !isSeeded,
              let sam = members.first(where: { $0.name == "Sam" }),
              let jordan = members.first(where: { $0.name == "Jordan" }) else { return }
        let household = SpotifyUser(id: "demo.household", name: "Home Speakers")
        let day: TimeInterval = 86_400
        spotify.accounts.link(.household, record: SpotifyAccountRecord(user: household, signedInAt: Date().addingTimeInterval(-40 * day)),
                              refreshToken: "demo")
        spotify.accounts.link(.member(sam.id), record: SpotifyAccountRecord(
            user: SpotifyUser(id: "demo.sam", name: "sam.listens"), signedInOn: "Sam's iPhone", signedInAt: Date().addingTimeInterval(-3 * day)
        ), refreshToken: "demo")
        spotify.accounts.link(.member(jordan.id), record: SpotifyAccountRecord(
            user: SpotifyUser(id: "demo.jordan", name: "Jordan R"), signedInOn: "Jordan's iPhone", signedInAt: Date().addingTimeInterval(-190 * day)
        ), refreshToken: "demo")
        spotify.accounts.forgetToken(of: .member(jordan.id))
        spotify.accounts.noteThisIPad(household)
        isSeeded = true
        spotify.followRecognizedMember()
    }
}
#endif
