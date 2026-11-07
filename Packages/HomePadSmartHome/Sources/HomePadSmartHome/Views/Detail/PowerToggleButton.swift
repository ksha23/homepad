import HomePadCore
import HomePadUI
import SwiftUI

/// A glass on and off capsule for the accessory's power, sized by `DetailControlMetrics`.
struct PowerToggleButton: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory

    var body: some View {
        let isOn = accessory.state.isOn == true
        Button {
            send(.setPower(!isOn), on: accessory)
        } label: {
            Label(isOn ? "Turn Off" : "Turn On", systemImage: "power")
        }
        .buttonStyle(.glassCapsule(size: metrics.button))
    }
}
