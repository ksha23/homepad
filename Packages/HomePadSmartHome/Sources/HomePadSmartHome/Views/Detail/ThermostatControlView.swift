import HomePadCore
import HomePadUI
import SwiftUI

/// "Cooling to 70" with up and down arrows, current temperature and humidity,
/// and a mode picker, after HomeView's thermostat screen. `AccessoryDetailView`
/// fills the screen behind it with the mode's color.
struct ThermostatControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    let accessory: HomeAccessory
    @State private var target: Double?
    @State private var sendTask: Task<Void, Never>?

    private static let modes: [HVACMode] = [.off, .heat, .cool, .auto]

    private var state: AccessoryState { accessory.state }
    private var step: Double { state.temperatureUnit == .celsius ? 0.5 : 1 }
    private var range: ClosedRange<Double> { state.temperatureUnit == .celsius ? 10...32 : 50...90 }
    private var shownTarget: Double { target ?? state.targetTemperature ?? state.currentTemperature ?? range.lowerBound }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)
            Text(heading).font(.largeTitle.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.xl) {
                arrow("chevron.down", label: "Lower") { adjust(-step) }
                Text(formatted(shownTarget))
                    .font(.display(metrics.thermostatSize, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shownTarget))
                    .frame(minWidth: metrics.thermostatSize * 1.3)
                arrow("chevron.up", label: "Raise") { adjust(step) }
            }
            .opacity(state.hvacMode == .off ? 0.4 : 1)
            HStack(spacing: Theme.Spacing.l) {
                if let current = state.currentTemperature {
                    Label("\(formatted(current))°", systemImage: "thermometer.medium")
                }
                if let humidity = state.humidity {
                    Label("\(Int(humidity.rounded()))%", systemImage: "humidity.fill")
                }
            }
            .font(.title)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Self.modes, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .animation(.smooth, value: shownTarget)
    }

    private var heading: String {
        guard let mode = state.hvacMode, mode != .off else { return "Off" }
        return "\(AccessoryPresentation.modeVerb(mode)) to"
    }

    private func formatted(_ value: Double) -> String {
        step < 1 ? value.formatted(.number.precision(.fractionLength(0...1))) : "\(Int(value.rounded()))"
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        GlassIconButton(symbol, label: label, size: metrics.heroButton, action: action)
            .disabled(state.hvacMode == .off)
    }

    /// Changes the shown target at once and sends it after a short pause, so several taps make one call.
    private func adjust(_ delta: Double) {
        let next = min(max(shownTarget + delta, range.lowerBound), range.upperBound)
        target = next
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            send(.setTargetTemperature(next), on: accessory)
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { target = nil }
        }
    }

    private func modeButton(_ mode: HVACMode) -> some View {
        let title = mode == .auto ? "Auto" : mode.rawValue.capitalized
        let isSelected = state.hvacMode == mode
        return Button(title) {
            if !isSelected { send(.setHVACMode(mode), on: accessory) }
        }
        // White reads on every mode's color, where the accent clashed with the
        // blue. Off, the screen is the page's own, so the text color reads there.
        .buttonStyle(.glassCapsule(size: metrics.button, tint: isSelected ? (colorScheme == .light ? .black : .white) : nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
