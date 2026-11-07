import SwiftUI

public extension View {
    /// The iPadOS edit-mode wiggle for rearrangeable items (Home Screen icons and
    /// widgets, Control Center tiles, shortcuts). Respects Reduce Motion.
    ///
    ///     tile.jiggle(isEditing)
    ///
    /// Every item reads the same clock, so a whole screen wiggles in step, and an
    /// item that appears mid-edit joins in time. `isPaused` holds a lifted item
    /// still without leaving edit mode, so nothing in it changes as it lifts.
    func jiggle(_ isActive: Bool, isPaused: Bool = false) -> some View {
        modifier(JiggleModifier(isActive: isActive, isPaused: isPaused))
    }

    /// Control Center's edit mode, as on iPadOS: items keep still and their
    /// outlines pulse, so Liquid Glass stays glass. Jiggling glass tiles had to
    /// turn to frosted material, because glass smears under a rotation.
    ///
    ///     tile.editPulse(isEditing)
    ///
    /// The shared components draw the pulse in their own shape
    /// (`editPulseBorder(in:)`), a circle around a round button and the tile's
    /// rounded rectangle around a tile. Only the outermost shape in an item
    /// pulses, so a panel's buttons stay quiet.
    func editPulse(_ isActive: Bool) -> some View {
        environment(\.isEditPulsing, isActive)
    }

    /// The edit pulse around `shape` inside an item in `editPulse` mode, and
    /// nothing otherwise. Components call it with the shape they draw.
    ///
    ///     content.glassEffect(.regular, in: Circle()).editPulseBorder(in: Circle())
    func editPulseBorder<S: InsettableShape>(in shape: S) -> some View {
        modifier(EditPulseBorder(shape: shape))
    }

    /// Liquid Glass in `shape`, or, while the view jiggles in edit mode, the
    /// frosted material `GlassTile` uses. Glass does not follow a rotation: under
    /// the jiggle's tilt a rounded rectangle's glass smeared into slabs past the
    /// tile, and changing the tilt every frame made those tiles shake. Circles
    /// and capsules looked right, so their glass can stay.
    ///
    ///     content.tileGlassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    func tileGlassEffect<S: InsettableShape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(TileGlassModifier(glass: glass, shape: shape))
    }
}

public extension EnvironmentValues {
    /// True inside an item that jiggles in edit mode (`jiggle(_:)`).
    @Entry var isJiggling = false
    /// True where Liquid Glass cannot be drawn, such as inside SwiftUI's
    /// `ImageRenderer`, which leaves a glass shape and everything in it empty.
    /// Glass tiles draw a thin material there instead, as while jiggling.
    @Entry var drawsGlassFlat = false
    /// True inside an item whose outline pulses in edit mode (`editPulse(_:)`),
    /// until the outermost shape in it draws the pulse.
    @Entry var isEditPulsing = false
}

private struct EditPulseBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.isEditPulsing) private var isPulsing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isPulsing {
            content
                // Only the outermost shape pulses, not every button in a panel.
                .environment(\.isEditPulsing, false)
                .overlay { PulsingOutline(shape: shape, isStill: reduceMotion) }
        } else {
            content
        }
    }
}

/// The outline that brightens and fades while an item is being edited. With
/// Reduce Motion it holds still, half bright.
private struct PulsingOutline<S: InsettableShape>: View {
    let shape: S
    let isStill: Bool
    @State private var isBright = false

    /// One brighten or fade.
    static var halfPeriod: TimeInterval { 0.9 }

    var body: some View {
        shape.strokeBorder(.primary, lineWidth: 2)
            .opacity(isStill ? 0.5 : (isBright ? 0.85 : 0.2))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !isStill else { return }
                withAnimation(.easeInOut(duration: Self.halfPeriod).repeatForever(autoreverses: true)) { isBright = true }
            }
    }
}

private struct TileGlassModifier<S: InsettableShape>: ViewModifier {
    let glass: Glass
    let shape: S
    @Environment(\.isJiggling) private var isJiggling
    @Environment(\.drawsGlassFlat) private var drawsGlassFlat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isJiggling || drawsGlassFlat {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.strokeBorder(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.15), lineWidth: 1))
        } else {
            content.glassEffect(glass, in: shape).editPulseBorder(in: shape)
        }
    }
}

struct JiggleModifier: ViewModifier {
    let isActive: Bool
    var isPaused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero

    /// One full wiggle, over and back.
    static let period: TimeInterval = 0.24
    /// How far an item's corners move each way, in points. The same angle on
    /// every item made wide widgets swing far more than icons.
    static let cornerTravel: Double = 2
    /// The largest angle, for small items such as icons.
    static let maximumDegrees: Double = 1.2

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            // A shared clock instead of an animation per item: separate animations
            // started at different moments and ran at slightly different speeds,
            // so items drifted apart, and their steps lagged on a full screen.
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: isPaused)) { context in
                content
                    .environment(\.isJiggling, true)
                    .rotationEffect(.degrees(isPaused ? 0 : Self.angle(at: context.date, size: size)))
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        } else {
            content
        }
    }

    /// The wiggle's angle at a moment: in step for every item, smaller for bigger items.
    static func angle(at date: Date, size: CGSize) -> Double {
        sin(2 * .pi * date.timeIntervalSinceReferenceDate / period) * amplitude(for: size)
    }

    /// Degrees each way that move the item's corners `cornerTravel` points.
    static func amplitude(for size: CGSize) -> Double {
        let halfDiagonal = (size.width * size.width + size.height * size.height).squareRoot() / 2
        guard halfDiagonal > 0 else { return maximumDegrees }
        return min(maximumDegrees, cornerTravel / halfDiagonal * 180 / .pi)
    }
}

/// The round "minus" button drawn on an item's corner in edit mode: a plain
/// translucent circle, as on iPadOS, not Liquid Glass. Gray with a white minus
/// in Dark, light gray with a black minus in Light.
///
///     tile.overlay(alignment: .topLeading) {
///         RemoveBadge("Remove Weather") { remove() }.offset(x: -10, y: -10)
///     }
public struct RemoveBadge: View {
    private let accessibilityLabel: String
    private let size: CGFloat
    private let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - accessibilityLabel: What VoiceOver reads, for example "Remove Music".
    ///   - size: Diameter in points.
    ///   - action: Called on tap.
    public init(_ accessibilityLabel: String, size: CGFloat = 30, action: @escaping () -> Void) {
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: size * 0.5, weight: .heavy))
                .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(colorScheme == .light ? Color(white: 0.9, opacity: 0.85) : Color(white: 0.5, opacity: 0.6)))
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
