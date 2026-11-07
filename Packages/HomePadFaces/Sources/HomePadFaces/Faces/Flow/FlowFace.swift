import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.flow`: generative fluid color that tells the time. A slowly
/// swaying mesh gradient with the time built from Liquid Glass drops over it,
/// like HomeView's Flow face: a 1 is a tall slab with a dot, a 0 a rounded
/// block and the colon two small spheres (`FlowGlyph`). As you come closer
/// the colors deepen and the digits grow toward you, and motion in the room
/// sends a ripple of light across the screen.
///
/// How close someone is sets the intensity. It eases to a new level on the
/// spring of the host's proximity curve (`Theme.Motion.proximitySpring`),
/// worked out on each frame (`FlowMotion.IntensityMove`) while the drops bob
/// gently with the clock. The digits change once a minute.
///
/// The time blocks the widget cells it covers (`FlowClockLayout.bounds`), so
/// widgets go above and below it, and beside it in portrait.
struct FlowFace: View {
    /// Only the mesh's colors: the face has no text or accent.
    static let color = FaceOption.color([.lavender, .ocean, .coral, .sage, .midnight], default: .lavender, roles: [])

    static let definition = FaceDefinition(
        id: "faces.flow", title: "Flow", summary: "Living color that tells the time and reacts as you move through the room",
        systemImage: "drop.halffull", sortOrder: 30, options: [color],
        widgets: .around(FaceContentRegion { _, size, insets in
            [FlowClockLayout.make([], size: size, insets: insets).bounds]
        })
    ) { FlowFace() }

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.faceAllowsMotion) private var allowsMotion
    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceKeepClear) private var keepClear
    @Environment(FacesRuntime.self) private var runtime
    @State private var intensity = FlowMotion.IntensityMove(settledAt: FlowMotion.intensity(for: ProximityLevel.far.rawValue))
    @State private var ripple = 1.0

    var body: some View {
        let isNight = condition == .night
        let hexes = FlowColors.meshHexes(for: configuration.color(Self.color), isNight: isNight)
        let colors = hexes.map { Color(hex: $0) }
        FaceTimeline(.frames(proximity >= .mid ? 30 : 15)) { date in
            let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400)
            let glyphs = FlowGlyph.glyphs(ClockText.parts(for: date, uses24Hour: ClockText.localeUses24Hour()).joined)
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    FlowField(intensity: intensity.value(at: Date(), spring: Theme.Motion.proximitySpring), time: time,
                              colors: colors, size: proxy.size,
                              layout: FlowClockLayout.make(glyphs, size: proxy.size, insets: clockInsets),
                              isNight: isNight)
                        // Drawn from the clock and the eased intensity on every
                        // frame, so no animation of a transaction may move it too.
                        .transaction { $0.animation = nil }
                    Circle()
                        .stroke(Color.white.opacity(0.5 * (1 - ripple)), lineWidth: side * 0.03)
                        .blur(radius: side * 0.02)
                        .frame(width: side * 1.6 * ripple, height: side * 1.6 * ripple)
                        .faceForeground()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityElement()
                .accessibilityLabel(Text(date, format: .dateTime.hour().minute()))
            }
        }
        .ignoresSafeArea()
        .opacity(isNight ? 0.6 : 1)
        // Glass widgets read the mesh's colors as a whole.
        .backdropTone(.average(hexes.map { FaceRGB(hex: $0).tone }))
        .onAppear { intensity = .init(settledAt: FlowMotion.intensity(for: proximity.rawValue)) }
        .onChange(of: proximity) { _, level in
            let target = FlowMotion.intensity(for: level.rawValue)
            // Without motion the face is not redrawn frame by frame, so it goes
            // straight to the new level.
            intensity = allowsMotion
                ? intensity.moving(to: target, at: Date(), spring: Theme.Motion.proximitySpring)
                : .init(settledAt: target)
        }
        .onChange(of: runtime.activity.motionPulse) {
            ripple = 0
            withAnimation(.easeOut(duration: 1.8)) { ripple = 1 }
        }
    }

    /// The face insets with as much room at the bottom as the Now Playing
    /// pill takes at the top, so the time shrinks a little around its center
    /// for the pill and never reaches a cell it did not block before.
    private var clockInsets: EdgeInsets {
        let balance = keepClear.balancedVertically.bottom - keepClear.bottom
        return EdgeInsets(top: faceInsets.top, leading: faceInsets.leading, bottom: faceInsets.bottom + balance,
                          trailing: faceInsets.trailing)
    }
}

/// The mesh and the time's drops at one moment, for an intensity from 0 to 1.
private struct FlowField: View {
    let intensity: Double
    let time: Double
    let colors: [Color]
    let size: CGSize
    let layout: FlowClockLayout
    let isNight: Bool

    var body: some View {
        let scale = FlowMotion.clockScale(intensity: intensity)
        let center = CGPoint(x: layout.bounds.midX, y: layout.bounds.midY)
        ZStack {
            MeshGradient(width: 3, height: 3, points: FlowMotion.meshPoints(time: time), colors: colors)
                .saturation(0.6 + 0.4 * intensity)
            GlassEffectContainer(spacing: layout.unit * 0.1) {
                // One layer the size of the face, so every drop is placed in
                // the face's coordinates. The container alone stacks its views.
                ZStack {
                    ForEach(Array(layout.placed.enumerated()), id: \.offset) { index, placed in
                        let frame = placed.frame
                        let drift = FlowMotion.drift(time: time, index: index)
                        FlowDrop(shape: FlowGlyphShape(glyph: placed.glyph),
                                 fill: FlowColors.dropFill(colors, index: index, isNight: isNight), isNight: isNight)
                            .frame(width: frame.width * scale, height: frame.height * scale)
                            .position(x: center.x + (frame.midX - center.x) * scale + drift.x * layout.unit,
                                      y: center.y + (frame.midY - center.y) * scale + drift.y * layout.unit)
                            .id(placed.glyph)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            // A digit that changes, once a minute, fades into the next.
            .animation(.smooth(duration: 0.8), value: layout.placed.map(\.glyph))
            // The drops are the time. Behind the Home Screen the colors sway alone.
            .faceForeground()
        }
    }
}

/// One glassy drop in a shape: a tinted gradient with a soft highlight and
/// rim, inside Liquid Glass so it bends the colors behind it on device.
private struct FlowDrop<S: Shape>: View {
    let shape: S
    let fill: LinearGradient
    let isNight: Bool

    var body: some View {
        // At night the light on the glass is red too.
        let light = isNight ? Theme.nightRed : Color.white
        shape
            .fill(fill)
            .overlay {
                shape.fill(LinearGradient(colors: [light.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center))
            }
            .overlay {
                shape.stroke(light.opacity(0.45), lineWidth: 1.5)
            }
            .glassEffect(.clear, in: shape)
            .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
    }
}

/// Mesh colors for each palette choice, and the tinted drop fills.
enum FlowColors {
    /// The nine colors of the 3 by 3 mesh as hex, row by row.
    static func meshHexes(for color: FaceColor, isNight: Bool) -> [String] {
        let hexes: [String]
        if isNight {
            hexes = ["#000000", "#1A0201", "#000000", "#2A0403", "#5A0907", "#1A0201", "#000000", "#2A0403", "#000000"]
        } else {
            switch color {
            case .ocean: hexes = ["#7FE3E8", "#1FA2C9", "#2B4FD8", "#1FA2C9", "#4C7DF0", "#7FE3E8", "#2B4FD8", "#7FE3E8", "#1FA2C9"]
            case .coral: hexes = ["#FFD07A", "#FF8A5C", "#E8457A", "#FF8A5C", "#F06292", "#FFD07A", "#E8457A", "#FFB07A", "#FF8A5C"]
            case .sage: hexes = ["#C7F2A7", "#37B38A", "#2E7DBE", "#37B38A", "#7FD6B0", "#C7F2A7", "#2E7DBE", "#9BE3C4", "#37B38A"]
            case .midnight: hexes = ["#B07CFF", "#3A2C9E", "#0E1145", "#3A2C9E", "#6B4CE6", "#B07CFF", "#0E1145", "#5A3CC8", "#3A2C9E"]
            default: hexes = ["#C9A6F5", "#F07ACB", "#4C7DF0", "#F59AD8", "#8EB6FF", "#F07ACB", "#4C7DF0", "#F07ACB", "#C9A6F5"]
            }
        }
        return hexes
    }

    /// A drop's fill: a soft gradient between two mesh colors, or the night red.
    static func dropFill(_ colors: [Color], index: Int, isNight: Bool) -> LinearGradient {
        if isNight {
            return LinearGradient(colors: [Theme.nightRed.opacity(0.85), Theme.nightRed.opacity(0.55)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [colors[(index * 2 + 1) % colors.count].opacity(0.9),
                                       colors[(index * 3 + 4) % colors.count].opacity(0.8)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
