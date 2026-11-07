import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center tile (2x2) with up to four favorite accessories, one full-width
/// row each, like HomeView's door lock tiles. Long names wrap to a second line,
/// and the tile shows as many rows as fit its cell at the current text size, so
/// it never spills onto the tiles below.
struct FavoriteAccessoriesControl: View {
    @Environment(UnifiedSmartHomeService.self) private var service

    var body: some View {
        let favorites = service.favorites
        if favorites.isEmpty {
            Text("No Favorites").font(.headline).foregroundStyle(.secondary)
        } else {
            ViewThatFits(in: .vertical) {
                ForEach(Array((1...min(favorites.count, 4)).reversed()), id: \.self) { count in
                    VStack(spacing: Theme.Spacing.controlGap) {
                        ForEach(favorites.prefix(count)) {
                            CompactAccessoryRow(accessory: $0, nameLines: 2).frame(maxHeight: .infinity)
                        }
                    }
                }
            }
            .nightModeAware()
            .accessoryCommandHost()
        }
    }
}
