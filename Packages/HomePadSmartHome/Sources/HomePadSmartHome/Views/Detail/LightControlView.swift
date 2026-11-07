import HomePadCore
import HomePadUI
import SwiftUI

/// Brightness as a level control the full height of the screen, as on HomeView,
/// with Turn Off and the color temperature and color presets the light has in
/// a column beside it.
struct LightControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory
    @State private var level = 0.0

    private static let temperatures: [(kelvin: Int, color: Color)] = [
        (2200, Color(red: 1.0, green: 0.62, blue: 0.25)), (2700, Color(red: 1.0, green: 0.74, blue: 0.42)),
        (3500, Color(red: 1.0, green: 0.86, blue: 0.68)), (4500, Color(red: 0.96, green: 0.95, blue: 0.92)),
        (6000, Color(red: 0.8, green: 0.88, blue: 1.0)),
    ]
    private static let hues: [Double] = [0, 30, 55, 130, 210, 280]

    var body: some View {
        let isDimmable = accessory.capabilities.contains(.brightness)
        HStack(spacing: Theme.Spacing.xl) {
            if isDimmable {
                LevelControl(value: $level, systemImage: "lightbulb.fill", tint: lightColor) { editing in
                    if !editing { send(.setBrightness(level), on: accessory) }
                }
                .frame(width: metrics.slider.width, height: metrics.slider.height)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                PowerToggleButton(accessory: accessory)
                if accessory.capabilities.contains(.colorTemperature) {
                    swatchRow("Temperature") {
                        ForEach(Self.temperatures, id: \.kelvin) { preset in
                            swatch(preset.color, isSelected: accessory.state.colorTemperatureKelvin.map { abs($0 - preset.kelvin) < 250 } ?? false) {
                                send(.setColorTemperature(kelvin: preset.kelvin), on: accessory)
                            }
                        }
                    }
                }
                if accessory.capabilities.contains(.color) {
                    swatchRow("Color") {
                        ForEach(Self.hues, id: \.self) { hue in
                            swatch(Color(hue: hue / 360, saturation: 0.8, brightness: 1), isSelected: accessory.state.hue.map { abs($0 - hue) < 12 } ?? false) {
                                send(.setHueSaturation(hue: hue, saturation: 0.8), on: accessory)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isDimmable ? .leading : .center)
        }
        .onAppear(perform: syncLevel)
        .onChange(of: accessory.state) { syncLevel() }
    }

    private var lightColor: Color {
        let state = accessory.state
        if let hue = state.hue, let saturation = state.saturation, saturation > 0.05, accessory.capabilities.contains(.color) {
            return Color(hue: hue / 360, saturation: saturation, brightness: 1)
        }
        if let kelvin = state.colorTemperatureKelvin {
            return Self.temperatures.min { abs($0.kelvin - kelvin) < abs($1.kelvin - kelvin) }?.color ?? .yellow
        }
        return Theme.tint(for: .light)
    }

    private func syncLevel() {
        level = accessory.state.isOn == true ? (accessory.state.brightness ?? 1) : 0
    }

    private func swatchRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            // Wraps in the narrower column of a portrait screen.
            FlowLayout(spacing: Theme.Spacing.s) { content() }
        }
    }

    private func swatch(_ color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: metrics.swatch, height: metrics.swatch)
                .overlay(Circle().strokeBorder(Color.primary, lineWidth: isSelected ? 4 : 0))
                .padding(3)
        }
        .buttonStyle(.plain)
    }
}
