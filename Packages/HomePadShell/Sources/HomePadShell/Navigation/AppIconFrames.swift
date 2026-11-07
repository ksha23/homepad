import HomePadUI
import SwiftUI

/// The Home Screen content's own coordinate space. Its host (`HomeScreenHost`) fills the window from
/// its top left corner, so it is the window's space at rest, and the Home Screen sitting back (a scale
/// of the host's layer) does not change it. Zoom sources inside measure themselves in it (`zoomSourceSpace`).
enum HomeIconSpace {
    static let name = "homepad.home-content"
}

/// The ids the shell's own zoom sources report under (`ZoomSource`). The Home Screen's
/// icons report under their app ID.
enum ZoomSourceID {
    /// An icon in the app grid, which is on screen over the Home Screen's icons.
    static func grid(_ appID: String) -> String { "grid/\(appID)" }

    /// A widget placed on the Home Screen, by its placed item.
    static func widget(_ itemID: String) -> String { "widget/\(itemID)" }

    /// A pill at the top of the screen, by what it shows. The face's and the Home Screen's
    /// pills share it, so an app opened from one lands in the one where it closes.
    static func pill(_ role: String) -> String { "pill/\(role)" }
}

extension AppIconTile {
    /// Reports the icon's square under `id`, for the window to land on, with the whole tile, label and all,
    /// as where a touch counts. The tile is as wide as its widest part and the icon sits at its top, centered.
    func recordsIconFrame(_ id: String, iconSize: CGFloat, isEnabled: Bool = true) -> some View {
        // A lifted copy under the finger is not where the icon lives.
        zoomSource(id, isEnabled: isEnabled) { tile in
            ZoomSource(frame: CGRect(x: tile.midX - iconSize / 2, y: tile.minY, width: iconSize, height: iconSize),
                       shape: .icon, hitFrame: tile)
        }
    }
}
