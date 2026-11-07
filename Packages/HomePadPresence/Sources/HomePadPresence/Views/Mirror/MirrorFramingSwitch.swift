import HomePadUI
import SwiftUI

/// Close-Up or Full Body, as one Liquid Glass capsule as tall as the Mirror's
/// round glass buttons, with the current view filled white.
struct MirrorFramingSwitch: View {
    @Binding var framing: MirrorFraming

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MirrorFraming.allCases) { option in
                let isSelected = option == framing
                Button {
                    framing = option
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(minHeight: Theme.Size.tapTarget - Theme.Spacing.s)
                        .background(isSelected ? Color.white : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.xs)
        .frame(height: Theme.Size.tapTarget)
        .glassEffect(.regular.interactive(), in: Capsule())
        .animation(Theme.Motion.standard, value: framing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mirror view")
    }
}
