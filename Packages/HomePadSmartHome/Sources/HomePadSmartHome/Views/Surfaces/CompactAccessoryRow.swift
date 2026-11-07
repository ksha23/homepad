import HomePadCore
import HomePadUI
import SwiftUI

/// An accessory as one full-width row for widgets, Control Center and group lists:
/// icon, then the name and status in large type, so long names stay readable.
/// Tapping runs the quick action (toggle, lock, open or close), or opens the full
/// controls when there is none. Pressing and dragging sets the level of lights,
/// fans and blinds. Unlocking still asks guests to confirm.
struct CompactAccessoryRow: View {
    @Environment(\.accessoryCommand) private var send
    @State private var suppression = LevelTapSuppression()
    @Environment(\.showAccessoryControls) private var showControls
    @Environment(\.controlCornerRadius) private var cornerRadius
    let accessory: HomeAccessory
    /// Lines the name may wrap to. Callers that measure their rows pass 2 so a
    /// long name wraps when there is room, instead of being cut off.
    var nameLines = 1

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        let isActive = AccessoryPresentation.isActive(accessory)
        let tint = Theme.tint(for: accessory.kind)
        let status = AccessoryPresentation.status(for: accessory)
        // The color fills the row to the accessory's level (a lamp at 80%, a fan
        // at 25%), not the whole row whenever it is on.
        HStack(spacing: Theme.Spacing.s) {
            IconBadge(accessory: accessory, diameter: IconBadge.rowDiameter)
            VStack(alignment: .leading, spacing: 0) {
                Text(accessory.name).font(.headline).lineLimit(nameLines)
                Text(status).font(.subheadline).opacity(0.75).lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.standard, value: status)
            }
            .fillAwareForeground()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .levelFill(AccessoryPresentation.fillFraction(of: accessory), tint: tint, in: shape)
        .background {
            if AccessoryPresentation.fillFraction(of: accessory) < 1 { Color.clear.controlSurface(shape) }
        }
        .accessoryChangeGlow(accessory, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: tap)
        .accessoryLevelDrag(accessory, cornerRadius: cornerRadius, suppression: suppression)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .accessibilityLabel("\(accessory.name), \(status)")
        .accessibilityAction(named: "Show Controls") { showControls(accessory) }
        .animation(.smooth, value: isActive)
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
