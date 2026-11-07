import SwiftUI

/// A large Control Center style slider: a glass capsule that fills from one
/// end, with an SF Symbol inside. Easy to hit from arm's length, and the whole
/// surface is the touch target (drag anywhere, no tiny thumb).
///
/// Set `showsValue` for a full-screen accessory control, like HomeView's
/// light and blind controls: the symbol and a big percentage sit in the
/// middle. Commit the value to a device in `onEditingChanged(false)`.
///
/// On its own it is a glass tile, as in Control Center. Inside a `GlassTile`
/// it is a control on the tile's glass: its empty part takes `controlSurface`
/// and its corners `\.controlCornerRadius`, like the tile's other controls.
///
/// Its drag starts the moment a finger lands, and SwiftUI gives a view's own
/// gesture precedence over those of the views around it. So a drag on the
/// slider stays with the slider, as in Control Center's scroll view, and does
/// not end as a tap or a long press of the tile or page it sits on.
///
///     BigSlider(value: $brightness, systemImage: "sun.max.fill")
///         .frame(width: 96, height: 220)
///
///     BigSlider(value: $level, systemImage: "lightbulb.fill", tint: .yellow, showsValue: true) { editing in
///         if !editing { send(.setBrightness(level)) }
///     }
public struct BigSlider: View {
    @Binding private var value: Double
    private let axis: Axis
    private let systemImage: String
    private let tint: Color
    private let showsValue: Bool
    private let onEditingChanged: (Bool) -> Void

    @State private var dragStartValue: Double?
    @Environment(\.colorScheme) private var colorScheme
    /// Set inside a `GlassTile`, where the slider is one of the tile's controls.
    @Environment(\.tileSurfaceTone) private var tileSurface
    @Environment(\.controlCornerRadius) private var controlCornerRadius
    /// Title 3's size at the current text size.
    @ScaledMetric(relativeTo: .title3) private var minimumSymbolSize: CGFloat = 20

    /// - Parameters:
    ///   - value: Value between 0 and 1.
    ///   - axis: `.vertical` fills from the bottom, `.horizontal` from the leading edge.
    ///   - systemImage: Symbol drawn near the start of the track, or in the middle with `showsValue`.
    ///   - tint: Fill color.
    ///   - showsValue: Shows the value as a big percentage in the middle. Use a colored tint with it.
    ///   - onEditingChanged: `true` when a drag starts, `false` when it ends. VoiceOver
    ///     adjustments call it with `true` and then `false`.
    public init(
        value: Binding<Double>, axis: Axis = .vertical, systemImage: String, tint: Color = .white,
        showsValue: Bool = false, onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.axis = axis
        self.systemImage = systemImage
        self.tint = tint
        self.showsValue = showsValue
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { proxy in
            let length = axis == .vertical ? proxy.size.height : proxy.size.width
            let thickness = axis == .vertical ? proxy.size.width : proxy.size.height
            let shape = RoundedRectangle(cornerRadius: cornerRadius(thickness: thickness), style: .continuous)
            ZStack(alignment: axis == .vertical ? .bottom : .leading) {
                Color.clear
                fill(length: length)
                if showsValue {
                    valueLabel(thickness: thickness)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: symbolSize(thickness: thickness), weight: .semibold))
                        .foregroundStyle(symbolColor)
                        .frame(width: thickness, height: thickness)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .clipShape(shape)
            .modifier(BigSliderSurface(shape: shape, isInTile: tileSurface != nil))
            .contentShape(Rectangle())
            .gesture(drag(length: length))
            .animation(.smooth(duration: 0.15), value: value)
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

    /// A tile of its own takes the tile's corners, rounded less when it is thin.
    /// In a `GlassTile` it takes the tile's control corners.
    private func cornerRadius(thickness: CGFloat) -> CGFloat {
        tileSurface == nil ? min(thickness * 0.42, Theme.Radius.tile) : controlCornerRadius
    }

    /// The symbol's point size: a share of the slider's thickness, as in Control
    /// Center's tiles, but never smaller than Title 3, the text beside a thin
    /// slider in a widget, and never more than fits across it.
    private func symbolSize(thickness: CGFloat) -> CGFloat {
        min(max(thickness * 0.3, minimumSymbolSize), thickness * 0.6)
    }

    /// `.primary` on the empty glass. Once the fill reaches the symbol, a
    /// soft black on light fills (white, yellow) and white on the rest.
    private var symbolColor: Color {
        guard value > 0.12 else { return .primary }
        return Color.foreground(on: tint, in: colorScheme) == .black ? .black.opacity(0.7) : .white
    }

    private var percent: Int {
        Int((value * 100).rounded())
    }

    private func valueLabel(thickness: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(percent)")
                    .font(.display(min(110, thickness * 0.4)))
                    .contentTransition(.numericText(value: value))
                Text("%").font(.display(40)).opacity(0.7)
            }
        }
        // The page's own color as a soft halo keeps the number readable where
        // it crosses from the fill onto the glass, in either appearance.
        .foregroundStyle(.primary)
        .shadow(color: Color.screenBackground.opacity(0.25), radius: 8)
    }

    @ViewBuilder
    private func fill(length: CGFloat) -> some View {
        let filled = length * CGFloat(min(max(value, 0), 1))
        if axis == .vertical {
            Rectangle().fill(tint.gradient).frame(height: filled)
        } else {
            Rectangle().fill(tint.gradient).frame(width: filled)
        }
    }

    private func drag(length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartValue == nil {
                    dragStartValue = value
                    onEditingChanged(true)
                }
                let delta = axis == .vertical ? -gesture.translation.height : gesture.translation.width
                let start = dragStartValue ?? value
                value = min(1, max(0, start + Double(delta / max(length, 1))))
            }
            .onEnded { _ in
                dragStartValue = nil
                onEditingChanged(false)
            }
    }
}

/// What the empty part of a `BigSlider` is drawn on: glass for a slider that is
/// a tile of its own, and inside a `GlassTile` the fill every control on the
/// tile's glass takes (`ControlFill`), so it shows over any backdrop.
private struct BigSliderSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let isInTile: Bool

    func body(content: Content) -> some View {
        if isInTile {
            content.controlSurface(shape)
        } else {
            content.tileGlassEffect(.regular, in: shape)
        }
    }
}
