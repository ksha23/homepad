import HomePadCore
import HomePadUI
import SwiftUI

/// Favorite accessories for the Home Screen and the Modular face. Medium,
/// large and tall show one full-width row per accessory, as many as fit the
/// tile at the current text size, so names like "Bedroom Ceiling Light" read
/// in full, and tall has room for about half as many again as large. Small
/// shows the first favorite as a single tile with its name on up to two lines.
///
/// It shows the Home app's favorites until someone picks this widget's own
/// accessories in Edit Widget (`FavoritesWidgetChoice`).
struct FavoritesWidget: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.widgetSettings) private var settings
    let size: WidgetSize
    /// The tallest a row grows when the tile has more room than favorites.
    @ScaledMetric(relativeTo: .headline) private var tallestRow: CGFloat = 72

    var body: some View {
        // Picked on any HomePad, so read as this HomePad knows them.
        let chosen = settings[FavoritesWidgetChoice.accessories].map { service.localIDs(for: $0) }
        let favorites = FavoritesWidgetChoice.shown(chosen, favorites: service.favorites, accessories: service.accessories)
        Group {
            if let first = favorites.first, size == .small {
                FavoriteTile(accessory: first)
            } else {
                GlassTile {
                    if favorites.isEmpty {
                        Label(chosen == nil ? "Add favorites in the Home app" : "Edit the widget to choose accessories",
                              systemImage: "star")
                            .font(.headline).foregroundStyle(.secondary)
                    } else {
                        rows(favorites)
                    }
                }
            }
        }
        .accessoryCommandHost()
    }

    /// The most rows a size offers, about four for each row of cells it covers.
    private var mostRows: Int { size.rows * 4 }

    /// The most rows whose natural height fits the tile.
    private func rows(_ favorites: [HomeAccessory]) -> some View {
        let most = min(favorites.count, mostRows)
        return ViewThatFits(in: .vertical) {
            ForEach(Array((1...most).reversed()), id: \.self) { count in
                VStack(spacing: Theme.Spacing.controlGap) {
                    ForEach(favorites.prefix(count)) { accessory in
                        CompactAccessoryRow(accessory: accessory, nameLines: 2)
                            .frame(maxHeight: tallestRow)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// One favorite filling a small widget, lit in its color when on like a Home app
/// tile: icon at the top, the name on up to two lines and its status. Tapping runs
/// the quick action and pressing and dragging sets the level.
private struct FavoriteTile: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.showAccessoryControls) private var showControls
    @State private var suppression = LevelTapSuppression()
    let accessory: HomeAccessory

    var body: some View {
        let isActive = AccessoryPresentation.isActive(accessory)
        let tint = Theme.tint(for: accessory.kind)
        let status = AccessoryPresentation.status(for: accessory)
        GlassTile(isHighlighted: isActive, tint: tint, fill: AccessoryPresentation.fillFraction(of: accessory)) {
            ViewThatFits(in: .vertical) {
                content(status: status, nameLines: 2, showsStatus: true)
                content(status: status, nameLines: 1, showsStatus: true)
                content(status: status, nameLines: 2, showsStatus: false)
            }
        }
        .accessoryChangeGlow(accessory, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .onTapGesture(perform: tap)
        .accessoryLevelDrag(accessory, cornerRadius: Theme.Radius.tile, suppression: suppression)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .accessibilityLabel("\(accessory.name), \(status)")
        .accessibilityAction(named: "Show Controls") { showControls(accessory) }
        .animation(.smooth, value: isActive)
    }

    private func content(status: String, nameLines: Int, showsStatus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            IconBadge(accessory: accessory, diameter: IconBadge.rowDiameter)
            Spacer(minLength: Theme.Spacing.xs)
            Text(accessory.name).font(.headline).lineLimit(nameLines)
            if showsStatus {
                Text(status).font(.subheadline).opacity(0.75).lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.standard, value: status)
            }
        }
        .fillAwareForeground()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tap() {
        guard !suppression.shouldIgnoreTap else { return }
        if let command = AccessoryPresentation.primaryCommand(for: accessory) {
            send(command, on: accessory)
        } else {
            showControls(accessory)
        }
    }
}
