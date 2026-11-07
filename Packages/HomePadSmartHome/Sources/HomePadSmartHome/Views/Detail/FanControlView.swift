import HomePadCore
import HomePadUI
import SwiftUI

/// Fan speed as a fill slider, with an on and off button.
struct FanControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory
    @State private var speed = 0.0

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            LevelControl(value: $speed, systemImage: "fan.fill", tint: Theme.tint(for: .fan)) { editing in
                if !editing { send(.setBrightness(speed), on: accessory) }
            }
            .frame(width: metrics.slider.width, height: metrics.slider.height)
            PowerToggleButton(accessory: accessory)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: sync)
        .onChange(of: accessory.state) { sync() }
    }

    private func sync() {
        speed = accessory.state.isOn == true ? (accessory.state.brightness ?? 1) : 0
    }
}
