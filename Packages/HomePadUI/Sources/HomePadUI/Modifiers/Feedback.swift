import HomePadCore
import SwiftUI

/// A button that answers a press the way iPadOS controls do: it sinks a little
/// and dims while the finger is down, then settles back. Use it for tiles, rows
/// and icons that draw their own look, which `.buttonStyle(.plain)` leaves
/// without feedback. With Reduce Motion it only dims.
///
///     Button(action: run) { SceneTile(scene) }
///         .buttonStyle(.pressable)
public struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat

    /// - Parameter scale: How far the label sinks while pressed. Large tiles
    ///   take a value nearer 1, so their edges move as little as an icon's.
    public init(scale: CGFloat = 0.96) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, scale: scale)
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    /// A plain button that sinks and dims while pressed. See `PressableButtonStyle`.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }

    /// A plain button that sinks to `scale` and dims while pressed.
    static func pressable(scale: CGFloat) -> PressableButtonStyle { PressableButtonStyle(scale: scale) }
}

private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }
}

public extension View {
    /// Lights the view's shape in `tint` for a moment each time `trigger`
    /// changes, then lets it fade: a tile whose light just turned on or off, a
    /// scene that just ran. The glow plays once per change and draws nothing in
    /// between, so an idle screen does no work for it. Change `trigger` only
    /// for changes worth noticing, such as on and off, not every new level.
    ///
    ///     tile.changeGlow(glowCount, tint: .yellow, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    func changeGlow<Trigger: Equatable, S: InsettableShape>(_ trigger: Trigger, tint: Color, in shape: S) -> some View {
        modifier(ChangeGlowModifier(trigger: trigger, tint: tint, shape: shape))
    }
}

struct ChangeGlowModifier<Trigger: Equatable, S: InsettableShape>: ViewModifier {
    let trigger: Trigger
    let tint: Color
    let shape: S
    @Environment(\.displayCondition) private var condition

    func body(content: Content) -> some View {
        // Red at night like everything else, also where no parent tints it.
        let tint = condition == .night ? Theme.nightRed : tint
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, glow in
            view.overlay {
                // Nothing at all at rest, not a clear layer.
                if glow > 0.01 {
                    shape.fill(tint.opacity(0.16 * glow))
                        .overlay(shape.strokeBorder(tint.opacity(0.85 * glow), lineWidth: 2))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        } keyframes: { _ in
            // Rises quickly and fades slowly, like a lamp warming and cooling.
            CubicKeyframe(1, duration: 0.2)
            CubicKeyframe(0, duration: 1.1)
        }
    }
}
