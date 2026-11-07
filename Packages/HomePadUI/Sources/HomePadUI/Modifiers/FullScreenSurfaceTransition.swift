import SwiftUI

/// How a full-screen surface comes and goes over the screen it covers, such as
/// an accessory's controls, a camera or a ringing timer: the whole surface
/// fades, and its content zooms into place from a little smaller (or larger).
/// Its page reaches the screen's edges in every frame, the shell's margin
/// included.
///
/// The page never scales. SwiftUI gives a view under a scale other than 1 no
/// safe area to extend into, so a page that ignores the safe area stops at the
/// shell's margin for as long as a zoom runs, and the margin shows the screen
/// underneath until the zoom has settled. Put `.fullScreenSurfaceContent()` on
/// the content, inside the page, to give it the zoom.
///
///     if let accessoryID {
///         AccessoryDetailView(accessoryID: accessoryID)
///             .transition(.fullScreenSurface)
///     }
///
///     ZStack {
///         Color.screenBackground.ignoresSafeArea()
///         controls.fullScreenSurfaceContent()
///     }
public struct FullScreenSurfaceTransition: Transition {
    /// The content's scale while the surface is hidden.
    let scale: CGFloat

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .environment(\.fullScreenSurfaceScale, phase.isIdentity ? 1 : scale)
    }
}

public extension Transition where Self == FullScreenSurfaceTransition {
    /// Fades a full-screen surface and zooms its content in from 97%.
    static var fullScreenSurface: FullScreenSurfaceTransition { FullScreenSurfaceTransition(scale: 0.97) }

    /// Fades a full-screen surface and zooms its content in from `scale`.
    static func fullScreenSurface(scale: CGFloat) -> FullScreenSurfaceTransition {
        FullScreenSurfaceTransition(scale: scale)
    }
}

public extension View {
    /// Zooms a full-screen surface's content as the surface comes and goes
    /// (`FullScreenSurfaceTransition`), and moves and shrinks it with the card
    /// while the surface is pulled down (`swipeDownToDismiss`). Put it on the
    /// content, never on the page. With Reduce Motion the content never scales
    /// and the surface only fades.
    func fullScreenSurfaceContent() -> some View {
        modifier(FullScreenSurfaceContent())
    }

    /// `fullScreenSurfaceContent()` with a glow or picture behind the content
    /// that belongs to the card, such as an accessory's color glowing from the
    /// top. It reaches the screen's edges, the shell's margin included, and
    /// moves and shrinks with the content, so the card moves as one piece. On
    /// the page it would stay still inside the moving card.
    ///
    /// A scaled view has no safe area, so `ignoresSafeArea()` inside it stops
    /// at the margin. The background reaches the screen's edges as measured
    /// outside the scale instead. Use it on content that fills the surface,
    /// over a page of a plain color.
    ///
    ///     ZStack {
    ///         Color.screenBackground.ignoresSafeArea()
    ///         controls.fullScreenSurfaceContent { glow }
    ///     }
    func fullScreenSurfaceContent<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        modifier(FullScreenSurfaceContentWithBackground(background: background()))
    }
}

extension EnvironmentValues {
    /// The scale a full-screen surface's content takes: 1 while the surface is
    /// shown and at rest, another scale while a `FullScreenSurfaceTransition`
    /// brings it or takes it away, and less while `swipeDownToDismiss` pulls
    /// it down. The two multiply.
    @Entry var fullScreenSurfaceScale: CGFloat = 1
    /// How far down a full-screen surface's content has moved: 0 at rest, the
    /// pull while `swipeDownToDismiss` pulls it down.
    @Entry var fullScreenSurfaceOffset: CGFloat = 0
}

private struct FullScreenSurfaceContent: ViewModifier {
    @Environment(\.fullScreenSurfaceScale) private var scale
    @Environment(\.fullScreenSurfaceOffset) private var offset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : scale)
            .offset(y: offset)
    }
}

private struct FullScreenSurfaceContentWithBackground<Background: View>: ViewModifier {
    let background: Background
    /// The content's frame and the screen's, in global coordinates, both
    /// measured outside the scale.
    @State private var frame: CGRect = .zero
    @State private var screen: CGRect = .zero

    /// How far the background reaches past the content: to the screen's edges.
    private var outset: EdgeInsets {
        guard !frame.isEmpty, !screen.isEmpty else { return EdgeInsets() }
        return EdgeInsets(top: max(0, frame.minY - screen.minY), leading: max(0, frame.minX - screen.minX),
                          bottom: max(0, screen.maxY - frame.maxY), trailing: max(0, screen.maxX - frame.maxX))
    }

    func body(content: Content) -> some View {
        content
            .background {
                background.padding(EdgeInsets(top: -outset.top, leading: -outset.leading,
                                              bottom: -outset.bottom, trailing: -outset.trailing))
            }
            .fullScreenSurfaceContent()
            // Measured inside `ignoresSafeArea()`, where it has the screen's size.
            .background {
                Color.clear
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { screen = $0 }
                    .ignoresSafeArea()
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame = $0 }
    }
}
