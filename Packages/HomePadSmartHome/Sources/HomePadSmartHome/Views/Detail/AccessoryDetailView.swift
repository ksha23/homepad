import HomePadCore
import HomePadUI
import SwiftUI

/// Full-screen controls for one accessory or group, opened from a tile, a widget
/// or the Control Center. Live: it re-reads the accessory from the service on
/// every change. The close button or a swipe down closes it, back to the Home
/// app as it was. A drag on a slider stays with the slider.
///
/// The page follows the appearance, with the accessory's color glowing from the
/// top. A thermostat that heats, cools or runs auto fills the screen with its
/// mode's color, and its text and glass then stay light on it in every appearance,
/// as on HomeView.
struct AccessoryDetailView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.proximity) private var proximity
    @Environment(\.displayCondition) private var displayCondition
    @Environment(\.colorScheme) private var colorScheme
    let accessoryID: HomeAccessory.ID
    let onClose: () -> Void
    /// The room the control has, which sizes its slider, circle and buttons.
    @State private var controlSpace = CGSize(width: 1000, height: 800)

    var body: some View {
        let accessory = service.allAccessories.first { $0.id == accessoryID }
        ZStack {
            page(for: accessory)
            VStack(spacing: Theme.Spacing.l) {
                header(accessory)
                if let accessory {
                    // The room is measured on an empty view, so a control sized
                    // to the whole of it never makes it grow.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onGeometryChange(for: CGSize.self, of: \.size) { controlSpace = $0 }
                        .overlay { control(for: accessory) }
                    if accessory.isGroup {
                        GroupMembersSection(members: service.members(of: accessory))
                    }
                    ExternalControlsLink(accessory: accessory)
                } else {
                    EmptyStateView("Not Available", message: "This accessory is no longer in your home.", systemImage: "questionmark.square.dashed")
                }
            }
            .padding(Theme.Spacing.l)
            .environment(\.detailControlMetrics, DetailControlMetrics(space: controlSpace, proximity: proximity))
            .fullScreenSurfaceContent { glow(for: accessory) }
        }
        .environment(\.colorScheme, isFilled(accessory) ? .dark : colorScheme)
        .nightModeAware()
        .swipeDownToDismiss(onDismiss: onClose)
        .accessoryCommandHost()
    }

    private func header(_ accessory: HomeAccessory?) -> some View {
        DetailHeader(
            accessory?.name ?? "Accessory",
            subtitle: accessory.map { [$0.room, status(for: $0)].compactMap { $0 }.joined(separator: " · ") },
            onClose: onClose
        )
    }

    private func status(for accessory: HomeAccessory) -> String {
        accessory.isGroup
            ? AccessoryPresentation.groupStatus(for: accessory, members: service.members(of: accessory))
            : AccessoryPresentation.status(for: accessory)
    }

    @ViewBuilder
    private func control(for accessory: HomeAccessory) -> some View {
        switch accessory.kind {
        case .light: LightControlView(accessory: accessory)
        case .thermostat: ThermostatControlView(accessory: accessory)
        case .lock: LockControlView(accessory: accessory)
        case .cover, .garageDoor: CoverControlView(accessory: accessory)
        case .fan where accessory.capabilities.contains(.brightness): FanControlView(accessory: accessory)
        case .mediaPlayer: MediaControlView(accessory: accessory)
        case .sensor: SensorDetailView(accessory: accessory)
        default: PowerControlView(accessory: accessory)
        }
    }

    /// A thermostat's mode color covers the whole screen.
    private func isFilled(_ accessory: HomeAccessory?) -> Bool {
        fill(for: accessory) == 1
    }

    private func tint(for accessory: HomeAccessory?) -> Color {
        accessory.map(DetailTint.color(for:)) ?? .gray
    }

    private func fill(for accessory: HomeAccessory?) -> Double? {
        accessory.flatMap { DetailTint.fillOpacity(for: $0, isNight: displayCondition == .night) }
    }

    /// The page, which stays still while the controls are swiped down: the
    /// appearance's color, or a thermostat's mode color.
    private func page(for accessory: HomeAccessory?) -> some View {
        ZStack {
            Color.screenBackground
            if let fill = fill(for: accessory) {
                Rectangle().fill(tint(for: accessory).gradient).opacity(fill)
            }
        }
        .animation(Theme.Motion.standard, value: tint(for: accessory))
        .ignoresSafeArea()
    }

    /// Everything but a thermostat glows with its color from the top of the
    /// screen. The glow belongs to the card, so it moves and shrinks with the
    /// controls when they are swiped down (`fullScreenSurfaceContent(background:)`).
    private func glow(for accessory: HomeAccessory?) -> some View {
        ZStack {
            if fill(for: accessory) == nil {
                RadialGradient(colors: [tint(for: accessory).opacity(0.45), .clear], center: .top, startRadius: 40, endRadius: 900)
            }
        }
        .animation(Theme.Motion.standard, value: tint(for: accessory))
    }
}
