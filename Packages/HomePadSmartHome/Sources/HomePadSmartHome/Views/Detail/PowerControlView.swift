import HomePadCore
import HomePadUI
import SwiftUI

/// Switches, outlets, purifiers, alarms, vacuums and anything else with one main action:
/// a glass power circle and the actions that kind needs.
struct PowerControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory

    private var isOn: Bool { accessory.state.isOn == true }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            Button {
                send(.setPower(!isOn), on: accessory)
            } label: {
                Image(systemName: AccessoryPresentation.symbol(for: accessory))
                    .font(.system(size: metrics.circle * 0.4, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : Color.primary)
                    .frame(width: metrics.circle, height: metrics.circle)
                    .background(Circle().fill(isOn ? Theme.tint(for: accessory.kind) : Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(accessory.capabilities.isEmpty)
            Text(AccessoryPresentation.status(for: accessory)).font(.display(metrics.statusSize))
            Spacer(minLength: 0)
            actions
        }
        .animation(.smooth, value: isOn)
    }

    @ViewBuilder
    private var actions: some View {
        switch accessory.kind {
        case .securitySystem:
            actionButton(isOn ? "Disarm" : "Arm Away", symbol: isOn ? "shield.slash" : "shield.lefthalf.filled", command: .setPower(!isOn))
        case .vacuum:
            HStack(spacing: Theme.Spacing.s) {
                actionButton("Start", symbol: "play.fill", command: .setPower(true))
                actionButton("Pause", symbol: "pause.fill", command: .pause)
                actionButton("Dock", symbol: "house.fill", command: .setPower(false))
            }
        default:
            EmptyView()
        }
    }

    private func actionButton(_ title: String, symbol: String, command: AccessoryCommand) -> some View {
        Button {
            send(command, on: accessory)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.glassCapsule(size: metrics.button))
    }
}
