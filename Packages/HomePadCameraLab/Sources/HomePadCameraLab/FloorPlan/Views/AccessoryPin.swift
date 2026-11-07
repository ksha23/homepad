import HomePadCore
import HomePadUI
import SwiftUI

/// An accessory on the floor plan: glows in its tint when on, dims when off,
/// and shows a warning ring when it does not respond.
///
/// It is also the palette's drag preview, which SwiftUI draws without the app's
/// environment, so it must never read an environment object.
struct AccessoryPin: View {
    let accessory: HomeAccessory
    var isArranging = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: accessory.kind.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.primary)
                .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                .background {
                    Circle().fill(isActive ? AnyShapeStyle(Theme.tint(for: accessory.kind)) : AnyShapeStyle(.ultraThinMaterial))
                }
                .overlay {
                    Circle().strokeBorder(accessory.state.isReachable ? Color.primary.opacity(0.4) : .red, lineWidth: accessory.state.isReachable ? 1 : 3)
                }
                .shadow(color: isActive ? Theme.tint(for: accessory.kind).opacity(0.7) : .clear, radius: 14)
                .overlay(alignment: .topTrailing) {
                    if isArranging {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.footnote.weight(.bold))
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            // A plan is a dense overview, so its labels take the dense floor,
            // Subheadline, rather than a row's Title 3 and Body. They sit on
            // the page color, so a wall or a piece of furniture under them
            // never runs into the letters.
            VStack(spacing: 0) {
                Text(accessory.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(accessory.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 2)
            .background(Color.screenBackground.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
        }
        .frame(width: 160)
        .animation(.smooth, value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isArranging ? "Drag to move" : (FloorPlanActions.command(for: accessory) == nil ? "" : "Double tap to toggle"))
    }

    private var isActive: Bool {
        switch accessory.kind {
        case .lock: accessory.state.lockState == .unlocked
        case .cover, .garageDoor: (accessory.state.position ?? 0) > 0.01
        case .sensor: accessory.state.isActive ?? false
        default: accessory.state.isOn ?? false
        }
    }
}

/// What tapping a pin does. Locks and security devices only show state:
/// HomeView requires a recognized person for those, so the plan never toggles them.
enum FloorPlanActions {
    static func command(for accessory: HomeAccessory) -> AccessoryCommand? {
        guard accessory.state.isReachable else { return nil }
        switch accessory.kind {
        case .light, .switchOutlet, .fan, .airPurifier:
            return .toggle
        case .cover:
            return (accessory.state.position ?? 0) > 0.01 ? .close : .open
        default:
            return nil
        }
    }
}
