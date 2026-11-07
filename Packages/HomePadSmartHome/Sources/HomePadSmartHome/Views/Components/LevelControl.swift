import HomePadUI
import SwiftUI

/// A light's brightness, a fan's speed or a blind's position as one big
/// surface, after HomeView's light screen: the color rises from the bottom to
/// the level, the symbol rides the fill line, and the level reads in numerals
/// about a fifth of the screen tall. Text is dark over the color and the
/// page's text color above it. A drag anywhere on the surface changes the level, as on
/// `BigSlider`. Commit to the device in `onEditingChanged(false)`.
///
/// Candidate for HomePadUI. There it can replace `BigSlider`'s `showsValue`,
/// which nothing uses since the accessory details moved to this.
///
///     LevelControl(value: $level, systemImage: "lightbulb.fill", tint: .yellow) { editing in
///         if !editing { send(.setBrightness(level)) }
///     }
struct LevelControl: View {
    @Binding var value: Double
    let systemImage: String
    let tint: Color
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragStartValue: Double?

    private var percent: Int { Int((min(max(value, 0), 1) * 100).rounded()) }

    var body: some View {
        GeometryReader { proxy in
            let layout = LevelControlLayout(size: proxy.size, level: value)
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            ZStack(alignment: .bottom) {
                Color.clear
                Rectangle().fill(tint.gradient).frame(height: layout.fillHeight)
                labels(layout, width: proxy.size.width)
                    .foregroundStyle(Color.primary)
                // The same labels again, dark, only where the color is.
                labels(layout, width: proxy.size.width)
                    .foregroundStyle(.black.opacity(0.75))
                    .mask(alignment: .bottom) { Rectangle().frame(height: layout.fillHeight) }
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .tileGlassEffect(.regular, in: shape)
            .contentShape(shape)
            .gesture(drag(height: proxy.size.height))
            .animation(.smooth(duration: 0.15), value: value)
            .animation(Theme.Motion.standard, value: layout.valueIsOnFill)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(Image(systemName: systemImage)))
        .accessibilityValue("\(percent) percent")
        .accessibilityAdjustableAction { direction in
            onEditingChanged(true)
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private func labels(_ layout: LevelControlLayout, width: CGFloat) -> some View {
        ZStack {
            Image(systemName: systemImage)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .position(x: width / 2, y: layout.symbolCenterY)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percent)")
                    .font(.display(layout.valueSize))
                    .contentTransition(.numericText(value: value))
                Text("%")
                    .font(.display(layout.valueSize * 0.4))
                    .opacity(0.7)
            }
            .lineLimit(1)
            .fixedSize()
            .position(x: width / 2, y: layout.valueCenterY)
        }
    }

    private func drag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartValue == nil {
                    dragStartValue = value
                    onEditingChanged(true)
                }
                let start = dragStartValue ?? value
                value = min(1, max(0, start - Double(gesture.translation.height / max(height, 1))))
            }
            .onEnded { _ in
                dragStartValue = nil
                onEditingChanged(false)
            }
    }
}
