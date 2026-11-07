import HomePadCore
import HomePadUI
import SwiftUI

/// One accessory on a glass tile. Tapping the icon runs the quick action (toggle,
/// lock, play, open or close). Tapping anywhere else opens the full controls.
/// Pressing and dragging sideways sets the level of a light, fan or blind.
/// Holding still shows the menu.
struct AccessoryTile: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.accessoryCommand) private var send
    @State private var suppression = LevelTapSuppression()
    @Environment(\.proximity) private var proximity
    let accessory: HomeAccessory
    let size: TileSize
    let onOpen: () -> Void

    private var isActive: Bool { AccessoryPresentation.isActive(accessory) }
    private var statusText: String {
        accessory.isGroup
            ? AccessoryPresentation.groupStatus(for: accessory, members: service.members(of: accessory))
            : AccessoryPresentation.status(for: accessory)
    }
    private var tint: Color { Theme.tint(for: accessory.kind) }

    var body: some View {
        // The color fills the tile to the accessory's level, not the whole tile.
        GlassTile(isHighlighted: isActive, tint: tint, fill: AccessoryPresentation.fillFraction(of: accessory)) {
            if size == .wide {
                HStack(spacing: Theme.Spacing.m) {
                    icon(isCompact: false)
                    labels(nameLines: 2)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            } else {
                // A long name gets its second line before it is cut off: the icon
                // shrinks to make room, and only then does the name stop at one line.
                ViewThatFits(in: .vertical) {
                    square(isCompact: false, nameLines: 2)
                    square(isCompact: true, nameLines: 2)
                    square(isCompact: false, nameLines: 1)
                }
            }
        }
        .accessoryChangeGlow(accessory, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .opacity(accessory.state.isReachable ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .onTapGesture { if !suppression.shouldIgnoreTap { onOpen() } }
        .accessoryLevelDrag(accessory, cornerRadius: Theme.Radius.tile, suppression: suppression)
        .contextMenu { AccessoryMenuItems(accessory: accessory, tileSize: size, onOpen: onOpen) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessory.name), \(statusText)")
        .accessibilityAction(named: "Show Controls", onOpen)
        .animation(.smooth, value: isActive)
    }

    private func square(isCompact: Bool, nameLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            icon(isCompact: isCompact)
            Spacer(minLength: Theme.Spacing.xs)
            labels(nameLines: nameLines)
        }
    }

    private func icon(isCompact: Bool) -> some View {
        let isNear = proximity >= .mid
        let side: CGFloat = isCompact ? (isNear ? 36 : 44) : (isNear ? 52 : 60)
        let symbolSize: CGFloat = isCompact ? side / 2 : (isNear ? 26 : 32)
        return Button {
            guard !suppression.shouldIgnoreTap else { return }
            if let command = AccessoryPresentation.primaryCommand(for: accessory) {
                send(command, on: accessory)
            } else {
                onOpen()
            }
        } label: {
            IconBadge(accessory: accessory, diameter: side, font: .system(size: symbolSize, weight: .semibold))
        }
        .buttonStyle(.pressable(scale: 0.9))
        .accessibilityLabel(AccessoryPresentation.primaryCommand(for: accessory) == nil ? "Show Controls" : "Quick Action")
    }

    private func labels(nameLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Names are Headline up close, so a long name keeps its second line
            // in a tile of the 11-inch's six columns, where Title 3 fits one.
            Text(accessory.name)
                .font(proximity >= .mid ? .headline : .title3.weight(.semibold))
                .lineLimit(nameLines)
            Text(statusText)
                .font(proximity >= .mid ? .tileDetail : .headline)
                .lineLimit(1)
                .opacity(0.75)
                .contentTransition(.numericText())
                // A new level or temperature rolls in, wherever it was set.
                .animation(Theme.Motion.standard, value: statusText)
        }
        .fillAwareForeground()
    }
}
