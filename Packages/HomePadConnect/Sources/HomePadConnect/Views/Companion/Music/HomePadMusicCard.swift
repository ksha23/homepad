import HomePadCore
import HomePadUI
import SwiftUI

/// The Music section of a HomePad's remote, as the Home app shows a HomePod:
/// the cover, what plays and where, play and pause, and the way into the player.
struct HomePadMusicCard: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    @State private var error: String?

    private var homePad: HomePadStatus? { connect.remote.status(of: peer.id) }
    private var status: RemoteMediaStatus? { connect.music.status(of: peer.id) }
    private var track: RemoteMediaStatus.Track? { status?.track }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Music", systemImage: "music.note")
            HStack(spacing: Theme.Spacing.m) {
                NavigationLink {
                    HomePadMusicView(peer: peer)
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        MusicArtwork(peerID: peer.id, cornerRadius: Theme.Radius.thumbnail)
                            .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track?.title ?? "Nothing Playing").font(.headline).lineLimit(1)
                            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            if track != nil, let status {
                                Label(status.routeName, systemImage: "hifispeaker.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let track, homePad?.supportsMusic == true {
                    GlassIconButton(track.isPlaying ? "pause.fill" : "play.fill", label: track.isPlaying ? "Pause" : "Play",
                                    size: Theme.Size.minTapTarget) {
                        send(track.isPlaying ? .pause : .play)
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var detail: String {
        if homePad?.supportsMusic == false {
            return homePad?.nowPlaying ?? "Update HomePad to control music."
        }
        if let track { return track.subtitle ?? (track.isPlaying ? "Playing" : "Paused") }
        return status == nil ? "Connecting" : "Choose something to play."
    }

    private func send(_ command: MediaCommand) {
        error = nil
        Task {
            do {
                try await connect.music.send(command, to: peer.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
