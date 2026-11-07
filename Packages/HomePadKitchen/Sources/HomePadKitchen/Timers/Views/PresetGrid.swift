import HomePadCore
import HomePadUI
import SwiftUI

/// One-tap timer presets from Kitchen settings.
struct PresetGrid: View {
    var columns = 3
    /// Height of each button. Tall buttons get larger text.
    var height: CGFloat = 56
    /// The most presets to show, for tiles with room for one row.
    var limit = KitchenSettings.maxPresets
    @Environment(AppServices.self) private var services
    @Environment(\.controlCornerRadius) private var cornerRadius

    var body: some View {
        let presets = Array(services.settings[KitchenSettings.presets].prefix(min(limit, KitchenSettings.maxPresets)))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.controlGap), count: columns),
                  spacing: Theme.Spacing.controlGap) {
            ForEach(presets) { preset in
                Button {
                    services.timers.start(duration: preset.seconds, label: preset.title)
                } label: {
                    Text(preset.title)
                        .font(height >= 96 ? .largeTitle.weight(.semibold) : (height >= 72 ? .title2.weight(.semibold) : .title3.weight(.semibold)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .buttonBorderShape(.roundedRectangle(radius: cornerRadius))
                .accessibilityLabel("Start a \(preset.title) timer")
            }
        }
    }
}
