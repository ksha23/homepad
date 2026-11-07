import HomePadCore
import HomePadUI
import SwiftUI

/// The top of the phone's player: cover, title, where it plays, progress,
/// transport and volume. Shows "Nothing Playing" when the HomePad has nothing.
struct MusicPlayerPanel: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    let status: RemoteMediaStatus
    /// Play or pause as tapped, shown until the HomePad's next status confirms it.
    @State private var expectedPlaying: Bool?
    @State private var error: String?

    private var track: RemoteMediaStatus.Track? { status.track }
    private var isPlaying: Bool { expectedPlaying ?? track?.isPlaying ?? false }
    private var receivedAt: Date { connect.music.receivedAt[peer.id] ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            MusicArtwork(peerID: peer.id, cornerRadius: Theme.Radius.tile)
                .frame(maxWidth: .infinity)
            titles
            if let track {
                MusicProgressBar(track: track, receivedAt: receivedAt, canSeek: status.canSeek) { send(.seek(seconds: $0)) }
                transport
                if let volume = status.volume {
                    MusicVolumeSlider(level: volume) { send(.setVolume(level: $0)) }
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        }
        .onChange(of: status) { expectedPlaying = nil }
        .animation(Theme.Motion.standard, value: track?.title)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(track?.title ?? "Nothing Playing")
                .font(.title2.bold())
                .lineLimit(2)
            if let subtitle = track?.subtitle {
                Text(subtitle).font(.body).foregroundStyle(.secondary).lineLimit(1)
            } else if track == nil {
                Text("Search below to play something on \(peer.name).").font(.body).foregroundStyle(.secondary)
            }
            Label(status.routeName, systemImage: "hifispeaker.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, Theme.Spacing.xs)
                .accessibilityLabel("Playing on \(status.routeName)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(track?.title)
        .transition(.opacity)
    }

    private var transport: some View {
        HStack(spacing: Theme.Spacing.l) {
            GlassIconButton("backward.fill", label: "Previous", size: Theme.Size.roundControl) { send(.previousTrack) }
            GlassIconButton(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play",
                            size: Theme.Size.heroControl, tint: .primary) {
                let playing = !isPlaying
                expectedPlaying = playing
                send(playing ? .play : .pause)
            }
            GlassIconButton("forward.fill", label: "Next", size: Theme.Size.roundControl) { send(.nextTrack) }
        }
        .frame(maxWidth: .infinity)
    }

    private func send(_ command: MediaCommand) {
        error = nil
        Task {
            do {
                try await connect.music.send(command, to: peer.id)
            } catch {
                expectedPlaying = nil
                self.error = error.localizedDescription
            }
        }
    }
}

/// The volume of what plays on the HomePad. Sent when the finger lifts, and
/// held there until the HomePad's reports catch up (`HeldVolume`).
struct MusicVolumeSlider: View {
    let level: Double
    let onCommit: (Double) -> Void
    @State private var held = HeldVolume(reported: 0)
    @State private var dragging: Double?
    /// True between a finger's touch and release, so only a drag changes the level (see `MusicProgressBar`).
    @State private var isDragging = false

    var body: some View {
        VolumeRow {
            Slider(value: Binding(get: { dragging ?? held.level }, set: { if isDragging { dragging = $0 } }), in: 0...1) { editing in
                if editing {
                    isDragging = true
                    return
                }
                guard isDragging else { return }
                isDragging = false
                guard let value = dragging else { return }
                held.choose(value, at: Date())
                dragging = nil
                onCommit(value)
            }
            .accessibilityLabel("Volume")
        }
        .frame(minHeight: Theme.Size.minTapTarget)
        .onAppear { held = HeldVolume(reported: level) }
        .onChange(of: level) { _, new in held.report(new, at: Date()) }
    }
}
