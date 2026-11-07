import HomePadCore
import HomePadUI
import SwiftUI

/// Blinds and doors: a fill slider for position when supported, and open, stop and close.
/// Garage doors ask guests to confirm before opening.
struct CoverControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory
    @State private var position = 0.0

    private var isOpen: Bool { AccessoryPresentation.isOpen(accessory.state) }

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if accessory.capabilities.contains(.position) {
                LevelControl(value: $position, systemImage: AccessoryPresentation.symbol(for: accessory),
                             tint: Theme.tint(for: accessory.kind)) { editing in
                    if !editing { send(.setPosition(position), on: accessory) }
                }
                .frame(width: metrics.slider.width, height: metrics.slider.height)
            } else {
                Image(systemName: AccessoryPresentation.symbol(for: accessory))
                    .font(.system(size: metrics.circle * 0.43, weight: .semibold))
                    .foregroundStyle(Theme.tint(for: accessory.kind))
                    .frame(width: metrics.circle, height: metrics.circle)
                    .glassEffect(.regular, in: .circle)
            }
            VStack(spacing: Theme.Spacing.s) {
                button("Open", symbol: "arrow.up", command: .open)
                if accessory.kind == .cover {
                    button("Stop", symbol: "stop.fill", command: .stop)
                }
                button("Close", symbol: "arrow.down", command: .close)
            }
            .frame(maxWidth: accessory.capabilities.contains(.position) ? .infinity : nil, alignment: .leading)
        }
        .onAppear { position = accessory.state.position ?? (isOpen ? 1 : 0) }
        .onChange(of: accessory.state) { position = accessory.state.position ?? (isOpen ? 1 : 0) }
    }

    private func button(_ title: String, symbol: String, command: AccessoryCommand) -> some View {
        Button {
            send(command, on: accessory)
        } label: {
            Label(title, systemImage: symbol).frame(minWidth: 120)
        }
        .buttonStyle(.glassCapsule(size: metrics.button))
    }
}
