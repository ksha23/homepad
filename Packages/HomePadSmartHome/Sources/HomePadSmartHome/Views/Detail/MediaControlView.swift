import HomePadCore
import HomePadUI
import SwiftUI

/// What is playing, transport controls and volume for a Home Assistant media player.
struct MediaControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    let accessory: HomeAccessory
    @State private var volume = 0.0

    private var isPlaying: Bool { accessory.state.isPlaying == true }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: metrics.circle * 0.45))
                .foregroundStyle(Theme.tint(for: .mediaPlayer))
                .frame(width: metrics.circle, height: metrics.circle)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            VStack(spacing: Theme.Spacing.xs) {
                Text(accessory.state.mediaTitle ?? (accessory.state.isOn == true ? "Not Playing" : "Off"))
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                if let artist = accessory.state.mediaArtist {
                    Text(artist).font(.title2).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.xl) {
                GlassIconButton("backward.fill", label: "Previous", size: metrics.transportButton) { send(.previousTrack, on: accessory) }
                GlassIconButton(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play", size: metrics.heroButton, tint: ink) {
                    send(isPlaying ? .pause : .play, on: accessory)
                }
                GlassIconButton("forward.fill", label: "Next", size: metrics.transportButton) { send(.nextTrack, on: accessory) }
            }
            if accessory.capabilities.contains(.volume) {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "speaker.fill")
                    Slider(value: $volume, in: 0...1) { editing in
                        if !editing { send(.setVolume(volume), on: accessory) }
                    }
                    .tint(ink)
                    Image(systemName: "speaker.wave.3.fill")
                }
                .font(.title3)
                .frame(maxWidth: 520)
            }
            Spacer(minLength: 0)
            PowerToggleButton(accessory: accessory)
        }
        .onAppear { volume = accessory.state.volume ?? 0 }
        .onChange(of: accessory.state.volume) { volume = accessory.state.volume ?? volume }
    }

    /// White on the dark page, black on the light one.
    private var ink: Color { colorScheme == .light ? .black : .white }
}
