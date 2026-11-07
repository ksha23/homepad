import HomePadUI
import SwiftUI

/// The cover of what plays on a HomePad: the image the HomePad attached, its
/// web cover, or a music note on glass when there is none.
struct MusicArtwork: View {
    @Environment(ConnectRuntime.self) private var connect
    let peerID: String
    let cornerRadius: CGFloat

    private var track: RemoteMediaStatus.Track? { connect.music.status(of: peerID)?.track }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { image }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if let cover = connect.music.cover(of: peerID) {
            Image(uiImage: cover).resizable().scaledToFill()
        } else if let url = track?.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .id(url)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        GeometryReader { proxy in
            Image(systemName: track?.sourceKind == .radio ? "dot.radiowaves.left.and.right" : "music.note")
                .font(.system(size: proxy.size.width * 0.36, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
    }
}
