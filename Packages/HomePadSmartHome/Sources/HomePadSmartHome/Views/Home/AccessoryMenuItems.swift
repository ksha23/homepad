import HomePadCore
import HomePadUI
import SwiftUI

/// The Home app's menu for an accessory, shared by tiles and sensor chips:
/// show its controls, favorite it, pick a tile size, hide it.
struct AccessoryMenuItems: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    let accessory: HomeAccessory
    /// The tile's size, for a tile. Sensor chips have no size to pick.
    var tileSize: TileSize?
    let onOpen: () -> Void

    var body: some View {
        if AccessoryPresentation.isControllable(accessory) {
            Button("Show Controls", systemImage: "slider.horizontal.3", action: onOpen)
        } else {
            Button("Show Details", systemImage: "chart.xyaxis.line", action: onOpen)
        }
        let isFavorite = service.favoriteAccessoryIDs.contains(accessory.id)
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
            service.setFavorite(accessory.id, isFavorite: !isFavorite)
        }
        if let tileSize {
            Picker("Tile Size", systemImage: "square.resize", selection: Binding(
                get: { tileSize },
                set: { service.layout.tileSizes[accessory.id] = $0 }
            )) {
                ForEach(TileSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        Button("Hide from Home", systemImage: "eye.slash", role: .destructive) {
            service.layout.setItem(accessory.id, room: accessory.room, visible: false)
        }
    }
}
