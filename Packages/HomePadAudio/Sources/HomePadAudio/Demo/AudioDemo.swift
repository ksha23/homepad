import Foundation
import HomePadCore
import Observation
import UIKit

/// Fixed content for simulator screenshots, which has no AirPlay speakers, no Apple
/// Music playback and no Home Assistant. Launch arguments:
///
///     -HomePadAudioDemo YES                       demo content for both music sources
///     -HomePadMusicSource thisIPad|musicAssistant start on this source
///     -HomePadAudioDemoSong YES                   show the song recognition card
///     -HomePadAudioDemoArtwork YES                give demo tracks a large square cover image,
///                                                 like real Apple Music artwork
///     -HomePadAudioDemoSkipEvery 3                skip to the next track every 3 seconds,
///                                                 to record transitions
///
/// With the demo on, `DemoMusicAssistantHome` stands in for Home Assistant and Music
/// Assistant, and `DemoPlaybackSource` for Apple Music on the iPad.
enum AudioDemo {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "HomePadAudioDemo") }
    static var showsSongCard: Bool { UserDefaults.standard.bool(forKey: "HomePadAudioDemoSong") }
    static var skipEvery: Double? {
        UserDefaults.standard.object(forKey: "HomePadAudioDemoSkipEvery") == nil ? nil : UserDefaults.standard.double(forKey: "HomePadAudioDemoSkipEvery")
    }

    /// The source named by `-HomePadMusicSource`, if any.
    static var launchSource: MusicSource? {
        UserDefaults.standard.string(forKey: "HomePadMusicSource").flatMap(MusicSource.init(rawValue:))
    }

    /// The iPad's own demo queue plays only when This iPad is the source, so a Music
    /// Assistant screenshot shows the house's music in Now Playing.
    static var startsLocalPlayback: Bool { launchSource != .musicAssistant }

    /// Saves `-HomePadMusicSource` as the household's choice. Spotify is turned
    /// on for it, so its setup state shows in the simulator, which cannot sign in.
    @MainActor
    static func applyLaunchSource(to settings: SettingsStore) {
        guard let launchSource else { return }
        settings[AudioSettings.musicSource] = launchSource.rawValue
        if launchSource == .spotify { settings[AudioSettings.spotifyEnabled] = true }
    }

    static let ports = [
        AudioRoutePort(name: "Living Room", uid: "demo-living", portType: AudioRoutePort.PortType.airPlay),
        AudioRoutePort(name: "Kitchen", uid: "demo-kitchen", portType: AudioRoutePort.PortType.airPlay),
    ]

    static let song = SongMatch(title: "Sunrise Avenue", artist: "The Demo Band")

    /// A 1200 point square cover per album, drawn once into the temporary folder,
    /// for checking layouts against real artwork sizes. Nil unless asked for.
    static func artworkURL(for album: String) -> URL? {
        guard UserDefaults.standard.bool(forKey: "HomePadAudioDemoArtwork") else { return nil }
        let seed = album.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-artwork-\(seed).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            let side: CGFloat = 1200
            let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
                let hue = CGFloat(seed) / 360
                UIColor(hue: hue, saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                UIColor(hue: (hue + 0.4).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.6, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6))
            }
            try? image.pngData()?.write(to: url)
        }
        return url
    }
}
