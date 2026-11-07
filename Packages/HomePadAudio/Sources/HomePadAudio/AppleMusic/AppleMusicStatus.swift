import Foundation
import HomePadCore
import MusicKit

/// Whether Apple Music works on this iPad right now, from a live catalog request
/// rather than from the permission alone. Exactly one of five answers, each with
/// a short fix, so the Music app never shows a blank screen.
enum AppleMusicStatus: Equatable, Sendable {
    case checking
    /// Catalog requests work and the subscription can play them.
    case ready
    /// Catalog requests work, or the account is not signed in, but nothing can play without a subscription.
    case needsSubscription
    /// The developer token request failed: the MusicKit App Service is not enabled for HomePad's bundle ID.
    case serviceNotEnabled
    /// HomePad may not use Media and Apple Music. `canAsk` is true before the first prompt.
    case notAuthorized(canAsk: Bool)
    /// Apple Music did not answer.
    case offline

    /// The short status line for Settings.
    var title: String {
        switch self {
        case .checking: "Checking"
        case .ready: "Ready"
        case .needsSubscription: "Needs Apple Music subscription"
        case .serviceNotEnabled: "MusicKit not enabled for HomePad"
        case .notAuthorized: "Not allowed"
        case .offline: "Offline"
        }
    }

    /// One or two plain sentences with the fix.
    var message: String {
        switch self {
        case .checking:
            "Checking Apple Music."
        case .ready:
            "Apple Music is ready."
        case .needsSubscription:
            "Playing from the Apple Music catalog needs a subscription. Sign in to the Music app with an account that has one. Your synced library still plays."
        case .serviceNotEnabled:
            "Apple Music needs the MusicKit App Service turned on for com.ksha23.homepad in the Apple Developer portal. Your synced library still plays."
        case .notAuthorized(let canAsk):
            canAsk
                ? "Allow HomePad to use Media and Apple Music to play your music here."
                : "Turn on Media and Apple Music for HomePad in the Settings app."
        case .offline:
            "Apple Music isn't reachable right now. Check the internet connection and try again."
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "hourglass"
        case .ready: "checkmark.circle.fill"
        case .needsSubscription: "music.note"
        case .serviceNotEnabled: "key.slash"
        case .notAuthorized: "lock.fill"
        case .offline: "wifi.slash"
        }
    }

    /// Catalog browsing works (recommendations, search), even if playback might not.
    var canBrowseCatalog: Bool { self == .ready }

    /// Sorts a MusicKit failure into a status. Unknown failures count as offline.
    static func classify(_ error: Error) -> AppleMusicStatus {
        if let tokenError = error as? MusicTokenRequestError {
            switch tokenError {
            case .developerTokenRequestFailed: return .serviceNotEnabled
            case .permissionDenied: return .notAuthorized(canAsk: false)
            case .userNotSignedIn, .userTokenRequestFailed, .userTokenRevoked, .privacyAcknowledgementRequired:
                return .needsSubscription
            case .unknown: return .offline
            @unknown default: return .offline
            }
        }
        if let dataError = error as? MusicDataRequest.Error, [401, 403].contains(dataError.status) {
            return .serviceNotEnabled
        }
        if error is URLError { return .offline }
        return .offline
    }
}

/// Runs the live check behind `AppleMusicStatus` and logs the exact MusicKit error.
enum AppleMusicProbe {
    private static let log = Log.make("Music")

    /// Authorization first, then a one-song catalog search, then the subscription.
    @MainActor
    static func run() async -> AppleMusicStatus {
        switch MusicAuthorization.currentStatus {
        case .notDetermined: return .notAuthorized(canAsk: true)
        case .denied, .restricted: return .notAuthorized(canAsk: false)
        case .authorized: break
        @unknown default: return .notAuthorized(canAsk: false)
        }
        do {
            var request = MusicCatalogSearchRequest(term: "hits", types: [Song.self])
            request.limit = 1
            _ = try await request.response()
        } catch {
            let status = AppleMusicStatus.classify(error)
            log.error("Catalog probe failed (\(status.title, privacy: .public)): \(String(reflecting: error), privacy: .public)")
            return status
        }
        do {
            let subscription = try await MusicSubscription.current
            return subscription.canPlayCatalogContent ? .ready : .needsSubscription
        } catch {
            log.error("Subscription check failed: \(String(reflecting: error), privacy: .public)")
            return .ready
        }
    }
}
