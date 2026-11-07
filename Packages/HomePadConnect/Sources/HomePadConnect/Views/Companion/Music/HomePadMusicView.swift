import HomePadCore
import HomePadUI
import SwiftUI

/// A HomePad's music on the phone, like the HomePod player in Apple's Home and
/// Music apps: the cover, title, the speakers it plays on, progress, transport
/// and volume, then the speakers to move it to and a search to start something.
/// It updates live while open, from the HomePad's pushes.
struct HomePadMusicView: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice

    private var homePad: HomePadStatus? { connect.remote.status(of: peer.id) }
    private var status: RemoteMediaStatus? { connect.music.status(of: peer.id) }
    /// False only once the HomePad said it speaks an older protocol.
    private var supportsMusic: Bool { homePad?.supportsMusic ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !supportsMusic {
                    UpdateHomePadNotice(name: peer.name, nowPlaying: homePad?.nowPlaying)
                } else if let status {
                    MusicPlayerPanel(peer: peer, status: status)
                    if !status.outputs.isEmpty {
                        MusicSpeakersSection(peer: peer, outputs: status.outputs)
                    }
                } else {
                    ProgressView("Connecting to \(peer.name)")
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.appIcon * 2)
                }
                MusicSearchSection(peer: peer, viaAssistant: !supportsMusic)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.inline)
        .watchesMusic(of: peer.id)
    }
}

/// Shown for a HomePad whose app is older than music control.
private struct UpdateHomePadNotice: View {
    let name: String
    let nowPlaying: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Update HomePad", systemImage: "arrow.down.app.fill").font(.headline)
            Text("Update HomePad on \(name) to control its music from here. Until then, the search below asks its assistant to play.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let nowPlaying {
                Label("Playing \(nowPlaying)", systemImage: "music.note").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
