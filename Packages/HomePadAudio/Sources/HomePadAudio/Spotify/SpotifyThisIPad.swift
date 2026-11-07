import Foundation

/// Which Spotify Connect device is the Spotify app on this iPad.
///
/// The Web API names devices and gives their type, nothing more, and iPadOS
/// gives HomePad no name to compare (it reads "iPad" without Apple's device
/// name entitlement). So HomePad learns the device's ID from what it can see,
/// and keeps it on this iPad (`AudioSettings.spotifyThisIPadID`):
/// - HomePad opened Spotify here, and a device that was not listed before shows
///   up. Spotify joins Connect when it opens, so that device is this iPad.
/// - Spotify plays on a tablet while another app's audio plays on this iPad and
///   HomePad's own players are quiet. The tablet that plays is this iPad.
///
/// A remembered ID that is still listed is never replaced, so another iPad
/// playing Spotify cannot take its place.
enum SpotifyThisIPad {
    struct Observation {
        var devices: [SpotifyDevice]
        /// The ID learned before, if any.
        var remembered: String?
        /// The device Spotify says plays now, nil while nothing plays.
        var playing: SpotifyDevice?
        /// Another app's audio plays on this iPad (`secondaryAudioShouldBeSilencedHint`).
        var otherAppPlaysHere: Bool
        /// HomePad's own Apple Music, library, radio or sleep sounds play, which
        /// iPadOS may count as another app's audio.
        var homePadPlays: Bool
        /// The devices listed just before HomePad opened Spotify here, while that wake lasts.
        var listedBeforeWake: Set<String>?
    }

    /// The device ID of the Spotify app on this iPad, or nil while HomePad cannot tell.
    static func identify(_ seen: Observation) -> String? {
        if let remembered = seen.remembered, seen.devices.contains(where: { $0.id == remembered }) {
            return remembered
        }
        if let before = seen.listedBeforeWake {
            let appeared = seen.devices.filter { !before.contains($0.id) }
            // Another device may join at the same moment. A tablet is this iPad's kind.
            if let device = appeared.count == 1 ? appeared.first : appeared.first(where: \.isTablet) {
                return device.id
            }
        }
        if let playing = seen.playing, playing.isTablet, seen.otherAppPlaysHere, !seen.homePadPlays {
            return playing.id
        }
        return seen.remembered
    }
}

extension SpotifyDevice {
    /// Spotify lists iPads as tablets.
    var isTablet: Bool { type.caseInsensitiveCompare("Tablet") == .orderedSame }
}

/// What HomePad can do when new Spotify music should play on this iPad but the
/// Spotify app here is not open, each with the words for the person.
enum SpotifyWake: Equatable {
    /// HomePad opens Spotify, and the music starts once Spotify has joined Connect.
    case openSpotify
    /// Guided Access or Single App Mode keeps HomePad on screen, and iPadOS then
    /// opens no other app, so the person leaves it first.
    case leaveGuidedAccess
    /// The Spotify app is not on this iPad.
    case installSpotify
    /// Spotify opened, but HomePad could not tell which Connect device is this iPad.
    case notIdentified
    /// Spotify opened, and the Spotify app here is signed in to someone else, named here.
    case signedInAsOther(String)

    /// The one HomePad can take now.
    static func advice(isInstalled: Bool, isGuidedAccess: Bool) -> SpotifyWake {
        if !isInstalled { return .installSpotify }
        return isGuidedAccess ? .leaveGuidedAccess : .openSpotify
    }

    var title: String {
        switch self {
        case .openSpotify, .leaveGuidedAccess: "Spotify Isn't Open"
        case .installSpotify: "Install Spotify"
        case .notIdentified: "Play Once in Spotify"
        case .signedInAsOther(let name): "Spotify Here Is \(name)'s"
        }
    }

    var message: String {
        switch self {
        case .openSpotify:
            "Spotify isn't open on this iPad. HomePad opens it, and the music starts once Spotify is up. Come back with the HomePad link at the top left."
        case .leaveGuidedAccess:
            "Spotify isn't open on this iPad, and Guided Access keeps HomePad on screen, so HomePad can't open it. Triple-click the top button and end Guided Access, then play again. HomePad opens Spotify and comes back with the music playing. Start Guided Access again after."
        case .installSpotify:
            "Spotify plays on this iPad through the Spotify app. Install it from the App Store, sign in, and come back."
        case .signedInAsOther(let name):
            "Spotify on this iPad is signed in as \(name), so it plays \(name)'s music, not yours. To play yours here, sign out in Spotify on this iPad, sign in as you, and play any song for a few seconds. Or pick your own phone, computer or speaker in Play On."
        case .notIdentified:
            "HomePad can't tell which Spotify device is this iPad yet. In Spotify on this iPad, play any song for a few seconds, then come back. HomePad remembers it from then on."
        }
    }
}
