import HomePadCore
import HomePadUI
import SwiftUI

/// Whose volume Now Playing's volume control sets. The full-screen player and
/// the Now Playing widget both follow it, so they always move the same level.
enum NowPlayingVolumeTarget: Equatable {
    /// A Music Assistant or Home Assistant speaker, sent when a drag ends.
    case remote(AudioOutput.ID)
    /// The Spotify Connect device that plays, sent when a drag ends.
    case spotify
    /// The AirPlay speakers Apple's player plays to (`MusicAirPlayVolume`). The
    /// system volume moved the iPad while the HomePods played on.
    case appleMusicSpeakers
    /// The AirPlay speakers the Spotify app on this iPad plays to, on the
    /// iPad's system route (`AudioMediaService.spotifyVolume`). The Web API
    /// sets no volume on a tablet, and the system volume follows HomePad's own
    /// sound, which stays on the iPad.
    case spotifySpeakers
    /// Apple's player where HomePad cannot read its speakers at all (an iPadOS
    /// without the shared output context). The AirPlay menu still has a slider
    /// for each speaker.
    case airPlayMenu
    /// The system volume: radio, sleep sounds, and the iPad when nothing plays.
    case system

    /// True when the AirPlay button sits beside the slider: the speakers are
    /// picked in AirPlay. Remote speakers and Spotify devices are picked in Play On.
    var showsAirPlayButton: Bool {
        [.appleMusicSpeakers, .spotifySpeakers, .system].contains(self)
    }

    /// The target for music on an AirPlay route HomePad reads: its speakers when
    /// they take a level. Speakers that read but refuse one are this iPad
    /// ("iPad, settable false" in the trace), whose level is the system volume.
    /// Showing the AirPlay menu there left Now Playing with no slider at all.
    /// Only a route HomePad cannot read at all leaves the AirPlay menu.
    static func airPlay(_ settable: NowPlayingVolumeTarget, canSetVolume: Bool, speakerName: String?) -> NowPlayingVolumeTarget {
        if canSetVolume { return settable }
        return speakerName == nil ? .airPlayMenu : .system
    }
}

extension AudioMediaService {
    /// Whose volume Now Playing's volume control sets, from where transport goes.
    var volumeTarget: NowPlayingVolumeTarget {
        if case .remote(let id) = transportTarget { return .remote(id) }
        if transportTarget == .spotify {
            guard spotify.playsHere else { return .spotify }
            return .airPlay(.spotifySpeakers, canSetVolume: spotifyVolume.canSetVolume, speakerName: spotifyVolume.speakerName)
        }
        if playsInApplesPlayer {
            return .airPlay(.appleMusicSpeakers, canSetVolume: musicVolume.canSetVolume, speakerName: musicVolume.speakerName)
        }
        return .system
    }
}

/// The volume control for `media.volumeTarget`, drawn as a row in the
/// full-screen player and as a bar in the widget.
struct NowPlayingVolumeSlider: View {
    var style: VolumeSliderStyle = .row
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        switch media.volumeTarget {
        case .remote(let id): RemoteVolumeSlider(outputID: id, style: style)
        case .spotify: SpotifyVolumeSlider(style: style)
        case .appleMusicSpeakers: MusicVolumeSlider(volume: media.musicVolume, style: style)
        case .spotifySpeakers: MusicVolumeSlider(volume: media.spotifyVolume, style: style)
        case .airPlayMenu: AirPlayVolumeButton()
        case .system: SystemVolumeSlider(style: style)
        }
    }
}

/// Opens the AirPlay menu, which has a volume slider for each speaker the music
/// plays on, including this iPad. A compact button, so it reads as a tap: a
/// full-width bar with a speaker at one end looked like a slider to drag.
/// Short of room, as in a widget, it shows only its symbol.
struct AirPlayVolumeButton: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        ViewThatFits(in: .horizontal) {
            GlassCapsuleButton("Speakers & Volume", systemImage: "airplayaudio", size: .regular) {
                media.showRoutePicker()
            }
            GlassIconButton("airplayaudio", label: "Speakers & Volume", size: Theme.Size.minTapTarget) {
                media.showRoutePicker()
            }
        }
        .accessibilityHint("Opens AirPlay, with a volume slider for each speaker.")
    }
}

/// The volume of the speakers Apple's player plays to, which follows changes
/// made elsewhere, such as the AirPlay menu.
struct MusicVolumeSlider: View {
    let volume: MusicAirPlayVolume
    var style: VolumeSliderStyle = .row
    /// The value under the finger while dragging, so readings never move the thumb back.
    @State private var dragging: Double?

    var body: some View {
        VolumeSlider(value: Binding(get: { dragging ?? Double(volume.volume) }, set: { value in
            dragging = value
            volume.set(Float(value))
        }), style: style, label: "\(volume.speakerName ?? "Speaker") volume") { editing in
            if !editing { dragging = nil }
        }
        .tint(.white)
    }
}

/// Volume for a remote speaker, sent when the drag ends.
struct RemoteVolumeSlider: View {
    let outputID: AudioOutput.ID
    var style: VolumeSliderStyle = .row
    @Environment(AudioMediaService.self) private var media
    @State private var level: Double = 0.4
    @State private var isEditing = false

    var body: some View {
        VolumeSlider(value: $level, style: style, label: "Speaker volume") { editing in
            isEditing = editing
            if !editing { Task { await media.setVolume(level) } }
        }
        .tint(.white)
        .onAppear { level = currentVolume ?? level }
        .onChange(of: currentVolume) { _, new in
            if !isEditing, let new { level = new }
        }
    }

    private var currentVolume: Double? {
        media.outputs.first { $0.id == outputID }?.volume
    }
}

/// Volume for the Spotify Connect device that plays, sent when the drag ends.
struct SpotifyVolumeSlider: View {
    var style: VolumeSliderStyle = .row
    @Environment(AudioMediaService.self) private var media
    @State private var level: Double = 0.4
    @State private var isEditing = false

    var body: some View {
        VolumeSlider(value: $level, style: style, label: "\(media.spotify.playback?.device?.name ?? "Spotify") volume") { editing in
            isEditing = editing
            if !editing { Task { await media.setVolume(level) } }
        }
        .tint(.white)
        .disabled(currentVolume == nil)
        .onAppear { level = currentVolume ?? level }
        .onChange(of: currentVolume) { _, new in
            if !isEditing, let new { level = new }
        }
    }

    /// Nil when the device has no volume Spotify can set.
    private var currentVolume: Double? {
        media.spotify.playback?.device?.volume
    }
}
