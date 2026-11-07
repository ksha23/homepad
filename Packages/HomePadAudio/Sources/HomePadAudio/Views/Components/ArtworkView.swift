import HomePadUI
import MediaPlayer
import MusicKit
import SwiftUI

/// Album art, station logo or a generated cover, with HomePad's card radius.
/// MusicKit artwork renders through `ArtworkImage` and library artwork through
/// `MPMediaItemArtwork`, since neither has a web URL.
struct ArtworkView: View {
    var artwork: Artwork?
    var libraryArtwork: MPMediaItemArtwork?
    var url: URL?
    var systemImage: String = "music.note"
    /// The item's name, for a generated cover when there is no artwork.
    var seed: String?
    var cornerRadius: CGFloat = Theme.Radius.card

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            content(side: side)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(side: CGFloat) -> some View {
        if let artwork {
            ArtworkImage(artwork, width: side, height: side)
        } else if let image = libraryArtwork?.image(at: CGSize(width: quantized(side), height: quantized(side))) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder(side: side)
                }
            }
        } else {
            placeholder(side: side)
        }
    }

    private func quantized(_ side: CGFloat) -> CGFloat {
        if side <= 100 { return 120 }
        if side <= 300 { return 300 }
        return 600
    }

    private func placeholder(side: CGFloat) -> some View {
        let style: GeneratedArtwork.Style = seed == nil ? .symbol : (cornerRadius >= side * 0.4 ? .monogram : .titled)
        return GeneratedArtwork(seed: seed ?? "Music", systemImage: systemImage, style: style)
    }
}
