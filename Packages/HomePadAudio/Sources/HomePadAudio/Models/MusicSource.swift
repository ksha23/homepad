import Foundation

/// Where the Music app finds and plays music. A curated choice of up to three.
enum MusicSource: String, CaseIterable, Identifiable, Sendable {
    /// Apple Music and the music library on this iPad, sent to speakers with AirPlay.
    case thisIPad
    /// Music Assistant in Home Assistant, which plays on HomePods, Sonos and groups by itself.
    case musicAssistant
    /// Spotify through Spotify Connect: HomePad browses and controls, a Connect device plays.
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisIPad: "This iPad"
        case .musicAssistant: "Music Assistant"
        case .spotify: "Spotify"
        }
    }

    var systemImage: String {
        switch self {
        case .thisIPad: "ipad.landscape"
        case .musicAssistant: "hifispeaker.2.fill"
        case .spotify: "dot.radiowaves.up.forward"
        }
    }

    /// One sentence for Settings.
    var detail: String {
        switch self {
        case .thisIPad: "Apple Music plays on this iPad. Choose speakers with AirPlay."
        case .musicAssistant: "Music Assistant plays on your HomePods and Sonos by itself, so the iPad stays free."
        case .spotify: "Spotify plays on your Spotify Connect speakers, phones and computers, and HomePad controls it."
        }
    }
}
