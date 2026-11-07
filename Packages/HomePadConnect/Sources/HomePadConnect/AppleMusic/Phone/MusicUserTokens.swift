import Foundation
import MusicKit

/// On a phone: the person's Music User Token, for a HomePad to read their
/// Apple Music library with.
@MainActor
protocol MusicUserTokenSource {
    /// The token of the Apple Account in this phone's Media & Purchases.
    /// `interactive` may ask the person for Apple Music access first, and
    /// `refresh` skips MusicKit's cache, for when a HomePad found the old one turned down.
    func userToken(interactive: Bool, refresh: Bool) async throws -> String
    /// False when Sync Library is off, so the library a HomePad reads is empty.
    /// Nil when MusicKit cannot say.
    func hasCloudLibrary() async -> Bool?
}

/// MusicKit's own tokens. The developer token is the one MusicKit makes for
/// HomePad's App ID (the MusicKit App Service), and the user token is made
/// for it by the system, for the account signed in on this phone.
///
/// Apple caps a developer token at six months. A user token has no lifetime
/// Apple documents. Developers report about six months, and it also stops
/// working when the person turns off HomePad's Apple Music access, signs out,
/// or their subscription lapses. MusicKit renews both on its own, so the
/// phone sends a HomePad the new token whenever the one MusicKit gives differs.
struct MusicKitUserTokens: MusicUserTokenSource {
    func userToken(interactive: Bool, refresh: Bool) async throws -> String {
        var status = MusicAuthorization.currentStatus
        if status == .notDetermined, interactive { status = await MusicAuthorization.request() }
        guard status == .authorized else { throw MusicTokenRequestError.permissionDenied }
        let provider = DefaultMusicTokenProvider()
        let options: MusicTokenRequestOptions = refresh ? .ignoreCache : []
        let developerToken = try await provider.developerToken(options: options)
        return try await provider.userToken(for: developerToken, options: options)
    }

    func hasCloudLibrary() async -> Bool? {
        try? await MusicSubscription.current.hasCloudLibraryEnabled
    }
}

extension MusicUserTokens {
    /// What to tell the person when MusicKit gave no token.
    static func explanation(_ error: Error) -> String {
        switch error as? MusicTokenRequestError {
        case .permissionDenied?:
            "Allow HomePad to use Apple Music on this iPhone, in Settings, Privacy & Security, Media & Apple Music."
        case .userNotSignedIn?:
            "Sign in to Apple Music on this iPhone first."
        case .privacyAcknowledgementRequired?:
            "Open the Music app on this iPhone once and accept Apple Music's privacy notice."
        case .developerTokenRequestFailed?:
            "Apple Music isn't turned on for HomePad yet. The MusicKit App Service has to be on for its App ID."
        case .userTokenRevoked?:
            "Apple Music access for HomePad was turned off. Allow it again in Settings."
        default:
            "Apple Music didn't give HomePad a token. Try again."
        }
    }
}

/// A namespace for the token helpers above.
enum MusicUserTokens {}

#if DEBUG
/// `-ConnectAppleMusicDemo YES`: a made-up token, since MusicKit cannot sign in on the simulator.
struct DemoMusicUserTokens: MusicUserTokenSource {
    func userToken(interactive: Bool, refresh: Bool) async throws -> String { "demo-music-user-token" }
    func hasCloudLibrary() async -> Bool? { true }
}
#endif
