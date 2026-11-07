import CoreGraphics
import SwiftUI

/// Where an open app's window is during the zoom: its size relative to the
/// screen and how far its center is from the screen's center. Full screen is
/// scale 1 at no offset. The navigator springs it, or the finger sets it, and
/// everything else about the window follows from it (`AppZoomGeometry.look`).
struct ZoomPose: Equatable, Sendable {
    var scale: CGFloat
    var offset: CGSize

    static let full = ZoomPose(scale: 1, offset: .zero)
}

/// The numbers of the app zoom, measured from iPadOS opening Calendar and
/// closing an app into its icon (60 fps recordings of the simulator's own Home
/// Screen, see `docs/APP_ZOOM.md`):
///
/// - The window keeps the screen's shape and stays fully opaque, with rounded
///   corners of about 40 points on screen the whole way.
/// - It turns into the icon only at the very end, from about twice the icon's
///   size: in a few frames its shape becomes the icon's square and the icon's
///   picture cross-dissolves in, so it lands as a copy of the icon.
/// - Its scale and position move together on one spring, which reads as the
///   screen zooming into the icon. During a swipe the window's bottom edge
///   stays under the finger and the window shrinks the higher it goes.
///
/// All rectangles are in window coordinates.
struct AppZoomGeometry: Equatable, Sendable {
    /// The window's corner radius on screen while it zooms.
    var cornerRadius: CGFloat = 40
    /// The corners reach `cornerRadius` once the window has shrunk this much, so
    /// an app coming to rest full screen loses them only in its last moment.
    var cornerEase: CGFloat = 0.06
    /// The window starts turning into its icon at this many times the icon's size.
    var morphFrom: CGFloat = 2
    /// By this many times the icon's size it has the icon's square shape and shows its picture.
    var faceBy: CGFloat = 1.4
    /// Into a widget the window turns over its flight, not at a size: a widget is so large that a size threshold
    /// was crossed by the finger alone, and the window dissolved before it went anywhere. While a finger holds the
    /// window it stays the app's picture. Once it flies, its shape and corners turn into the widget's over the
    /// whole way, together with the shrinking, and it melts into the widget from this share of the way on
    /// (0 where it set off, 1 on the widget). Late, as an icon's picture comes in late: melting from a third of
    /// the way, a window let go after a swipe toward a large widget (Home Favorites) faded where it was and
    /// never seemed to reach the widget.
    var widgetFadeStart: CGFloat = 0.7

    /// How far a window flying to a widget has turned into it: its shape and corners, and how much it has
    /// melted into the widget.
    struct WidgetTurn: Equatable, Sendable {
        var shape: CGFloat
        var fade: CGFloat
    }
    /// A swipe up: how much the window shrinks for each screen height of travel.
    var dragShrink: CGFloat = 1.1
    /// The smallest a swipe shrinks the window to while the finger is down.
    var dragMinScale: CGFloat = 0.35
    /// With no icon to land on (another page, a folder, Siri), the window zooms
    /// into an icon this big at the screen's center and fades from there.
    var fallbackIconSide: CGFloat = 110
    /// How far the Home Screen's content sits back (scaled down) while an app is open.
    var homeRecession: CGFloat = 0.05
    /// How dark the Home Screen gets while an app is open.
    var homeDim: CGFloat = 0.22
    /// How blurred the Home Screen is while an app is open, in points.
    var homeBlurRadius: CGFloat = 24

    static let standard = AppZoomGeometry()

    /// How the window looks at one pose. `maskSize` and `cornerRadius` are in
    /// the app's own unscaled space, so on screen they are `scale` times smaller.
    struct Look: Equatable, Sendable {
        var maskSize: CGSize
        var cornerRadius: CGFloat
        /// How much of the icon's picture shows over the app, 0 to 1.
        var iconFace: CGFloat
    }

    /// The icon to land on, or nil when there is none worth landing on: it is
    /// missing, empty or not fully on screen.
    func target(icon: CGRect?, screen: CGRect) -> CGRect? {
        guard let icon, icon.width > 0, icon.height > 0 else { return nil }
        return screen.insetBy(dx: -2, dy: -2).contains(icon) ? icon : nil
    }

    /// The icon-sized square at the screen's center, for a zoom with no icon to land on.
    func fallbackIcon(screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - fallbackIconSide / 2, y: screen.midY - fallbackIconSide / 2,
               width: fallbackIconSide, height: fallbackIconSide)
    }

    /// The window sitting on `icon`, an app icon or a widget: shrunk until the target's shape, fitted inside the
    /// screen, is the target's size, its center the target's center. For a square icon the window's shorter side
    /// is the icon's side.
    func iconPose(icon: CGRect, screen: CGRect) -> ZoomPose {
        ZoomPose(scale: 1 / fit(icon.size, in: screen),
                 offset: CGSize(width: icon.midX - screen.midX, height: icon.midY - screen.midY))
    }

    /// How many times `target` fits into the screen: the factor that makes the target's shape, at the screen's
    /// scale, as large as fits inside the screen.
    private func fit(_ target: CGSize, in screen: CGRect) -> CGFloat {
        guard target.width > 0, target.height > 0 else { return 1 }
        return min(screen.width / target.width, screen.height / target.height)
    }

    /// The window under a finger that has moved `translation` from the bottom edge (negative is up).
    /// Its bottom edge stays under the finger, and it shrinks the higher the finger goes.
    func dragPose(translation: CGSize, screen: CGRect) -> ZoomPose {
        let up = max(0, -translation.height)
        let scale = max(dragMinScale, 1 - dragShrink * up / screen.height)
        // Moving the center by this keeps the bottom edge (center plus half the scaled height) on the finger.
        let lift = min(0, translation.height) + (1 - scale) * screen.height / 2
        return ZoomPose(scale: scale, offset: CGSize(width: translation.width, height: lift))
    }

    /// The window at `pose`, heading for (or coming from) an icon `iconSide` points across with corners
    /// of `iconCornerRadius`. Above `morphFrom` times the icon's size it is the screen's shape with rounded
    /// corners. Below, it becomes the icon's square and shows the icon's picture.
    func look(at pose: ZoomPose, screen: CGRect, iconSide: CGFloat, iconCornerRadius: CGFloat) -> Look {
        look(at: pose, screen: screen, target: CGSize(width: iconSide, height: iconSide), cornerRadius: iconCornerRadius)
    }

    /// The window at `pose`, heading for (or coming from) a target of `target`'s size with corners of `cornerRadius`:
    /// an app icon, or a widget the app was opened from. Below `morphFrom` times the target's size the window takes
    /// the target's shape (a square for an icon) and shows its face.
    /// - Parameter widgetTurn: Into a widget, how far the window has turned into it (`widgetTurn(closeness:)`),
    ///   which replaces the size-based change an icon uses.
    func look(at pose: ZoomPose, screen: CGRect, target: CGSize, cornerRadius targetCornerRadius: CGFloat,
              widgetTurn: WidgetTurn? = nil) -> Look {
        let scale = max(pose.scale, 0.001)
        let factor = fit(target, in: screen)
        // The target's shape in the app's own unscaled space, as large as fits inside the screen.
        let shape = CGSize(width: target.width * factor, height: target.height * factor)
        let iconScale = 1 / factor
        // The shape and the picture finish together, so the window is never a square picture inside a taller
        // window. From there on it is the icon's picture shrinking onto the icon, like iPadOS.
        let change = smooth((morphFrom * iconScale - scale) / ((morphFrom - faceBy) * iconScale))
        let morph = widgetTurn?.shape ?? change
        let face = widgetTurn?.fade ?? change
        let rounding = smooth((1 - scale) / cornerEase)
        // In the target's shape the window has the target's corners for its size, which are its own when it lands.
        let iconCorners = targetCornerRadius * factor * scale
        let radius = lerp(cornerRadius * rounding, iconCorners, morph)
        return Look(
            maskSize: CGSize(width: lerp(screen.width, shape.width, morph), height: lerp(screen.height, shape.height, morph)),
            cornerRadius: radius / scale,
            iconFace: face
        )
    }

    /// How far a window flying to a widget has turned into it, from `closeness`, the share of the way it has come.
    func widgetTurn(closeness: CGFloat) -> WidgetTurn {
        WidgetTurn(shape: smooth(closeness), fade: smooth((closeness - widgetFadeStart) / (1 - widgetFadeStart)))
    }

    /// How fast the window under a finger moving at `fingerVelocity` (points per second) is changing,
    /// for the spring that takes over when it lets go: the derivative of `dragPose`.
    func dragVelocity(_ fingerVelocity: CGSize, at pose: ZoomPose, screen: CGRect) -> PoseVector {
        let shrinking = pose.scale > dragMinScale && pose.scale < 1 || fingerVelocity.height < 0 && pose.scale >= 1
        let scaleSpeed = shrinking ? dragShrink * fingerVelocity.height / screen.height : 0
        let lift = fingerVelocity.height - scaleSpeed * screen.height / 2
        return PoseVector(scaleSpeed, AnimatablePair(fingerVelocity.width, lift))
    }

    /// How far the Home Screen's content is scaled while an app is open over it.
    func homeScale(receded: Bool) -> CGFloat { receded ? 1 - homeRecession : 1 }

    /// How dark the Home Screen is while an app is open over it.
    func homeDimming(receded: Bool) -> CGFloat { receded ? homeDim : 0 }

    /// How blurred the Home Screen is while an app is open over it.
    func homeBlur(receded: Bool) -> CGFloat { receded ? homeBlurRadius : 0 }

    /// Ease in and out over 0 to 1.
    private func smooth(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

/// A pose as a vector a spring can move: scale, then the offset's width and height.
typealias PoseVector = AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>

extension AnimatablePair where First == CGFloat, Second == AnimatablePair<CGFloat, CGFloat> {
    init(_ pose: ZoomPose) {
        self.init(pose.scale, AnimatablePair<CGFloat, CGFloat>(pose.offset.width, pose.offset.height))
    }

    var pose: ZoomPose {
        ZoomPose(scale: first, offset: CGSize(width: second.first, height: second.second))
    }
}
