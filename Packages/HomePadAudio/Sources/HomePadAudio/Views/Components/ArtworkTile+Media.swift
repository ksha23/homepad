import HomePadUI
import MusicKit
import SwiftUI

extension ArtworkTile where Artwork == ArtworkView {
    /// An `ArtworkTile` that draws MusicKit artwork, a remote image or a
    /// symbol placeholder, for Apple Music and radio browse rows.
    init(
        title: String, subtitle: String? = nil, artwork: MusicKit.Artwork? = nil, artworkURL: URL? = nil,
        systemImage: String = "music.note", isActive: Bool = false, action: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, isActive: isActive, action: action) {
            ArtworkView(artwork: artwork, url: artworkURL, systemImage: systemImage, seed: title)
        }
    }
}
