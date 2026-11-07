import SwiftUI
import UIKit

/// Where the app zoom is drawn: a full-screen layer above the open app, empty
/// except while an app is zooming. `ZoomAnimator` puts the app's picture in it.
struct ZoomOverlay: UIViewRepresentable {
    let animator: ZoomAnimator

    func makeUIView(context: Context) -> ZoomOverlayView {
        let view = ZoomOverlayView()
        animator.attach(view)
        return view
    }

    func updateUIView(_ view: ZoomOverlayView, context: Context) {}
}

/// The app as one window: its picture (a snapshot of the screen, or a plain
/// page while it launches) inside a rounded window that clips it, and the
/// app's icon picture over it as it becomes the icon. Every pose is a handful
/// of layer properties (`LayerState`), set at once for a finger (`apply`) or
/// played as Core Animation keyframes for a spring (`play`).
final class ZoomOverlayView: UIView {
    /// Every layer of the window at one pose: the window's size, place, corners and opacity, the picture's
    /// scale inside it, and the icon picture's square and opacity. Both the picture and the icon stay
    /// centered in the window.
    struct LayerState {
        var windowSize: CGSize
        var windowCenter: CGPoint
        var cornerRadius: CGFloat
        var windowAlpha: CGFloat = 1
        var contentScale: CGFloat
        var iconSide: CGFloat
        var iconFace: CGFloat
    }

    /// The window: clips to its rounded shape, sits where the pose puts it.
    private let windowView = UIView()
    private let iconView = UIImageView()
    private var content: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        windowView.clipsToBounds = true
        windowView.layer.cornerCurve = .continuous
        windowView.isHidden = true
        iconView.contentMode = .scaleToFill
        addSubview(windowView)
        windowView.addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Puts `picture` (the size of the screen) in the window, with `icon` ready over it.
    func load(_ picture: UIView, icon: UIImage?) {
        content?.removeFromSuperview()
        content = picture
        picture.bounds = CGRect(origin: .zero, size: bounds.size)
        windowView.insertSubview(picture, belowSubview: iconView)
        iconView.image = icon
        windowView.isHidden = false
    }

    /// Empties the overlay and hands back the picture it showed.
    @discardableResult
    func unload() -> UIView? {
        removeAnimations()
        let picture = content
        picture?.removeFromSuperview()
        picture?.transform = .identity
        content = nil
        windowView.isHidden = true
        windowView.alpha = 1
        return picture
    }

    /// The layers at `pose` with `look`: the picture is scaled about the window's center, the window clips it
    /// to the look's shape and corners, and the icon picture fills the window's square.
    func state(pose: ZoomPose, look: AppZoomGeometry.Look) -> LayerState {
        let scale = pose.scale
        let size = CGSize(width: look.maskSize.width * scale, height: look.maskSize.height * scale)
        return LayerState(windowSize: size,
                          windowCenter: CGPoint(x: bounds.midX + pose.offset.width, y: bounds.midY + pose.offset.height),
                          cornerRadius: look.cornerRadius * scale, contentScale: scale,
                          iconSide: min(size.width, size.height), iconFace: look.iconFace)
    }

    /// Sets the layers to `state` at once, as a finger moves the window, ending any spring that was playing.
    func apply(_ state: LayerState) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        removeAnimations()
        setModel(state)
        CATransaction.commit()
    }

    /// Plays `states`, evenly spaced over `duration`, as Core Animation keyframes. The render server moves the
    /// window at the screen's full rate, whatever the main thread is doing meanwhile. The layers keep the last
    /// state. `completion` runs when the keyframes end, or when something else takes the window over.
    func play(_ states: [LayerState], duration: CFTimeInterval, completion: @escaping () -> Void) {
        guard let last = states.last, states.count > 1 else { return completion() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        removeAnimations()
        setModel(last)
        let times = states.indices.map { NSNumber(value: Double($0) / Double(states.count - 1)) }
        func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any]) {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = times
            animation.duration = duration
            animation.calculationMode = .linear
            layer.add(animation, forKey: Self.animationPrefix + keyPath)
        }
        let centers = states.map { NSValue(cgPoint: CGPoint(x: $0.windowSize.width / 2, y: $0.windowSize.height / 2)) }
        animate(windowView.layer, "bounds.size", states.map { NSValue(cgSize: $0.windowSize) })
        animate(windowView.layer, "position", states.map { NSValue(cgPoint: $0.windowCenter) })
        animate(windowView.layer, "cornerRadius", states.map { $0.cornerRadius })
        animate(windowView.layer, "opacity", states.map { Float($0.windowAlpha) })
        if let layer = content?.layer {
            animate(layer, "transform", states.map { NSValue(caTransform3D: CATransform3DMakeScale($0.contentScale, $0.contentScale, 1)) })
            animate(layer, "position", centers)
        }
        animate(iconView.layer, "bounds.size", states.map { NSValue(cgSize: CGSize(width: $0.iconSide, height: $0.iconSide)) })
        animate(iconView.layer, "position", centers)
        animate(iconView.layer, "opacity", states.map { Float($0.iconFace) })
        CATransaction.commit()
    }

    /// When the keyframes playing now began, on the `CACurrentMediaTime()` clock, once Core Animation has
    /// started them. Nil before that, or when none are playing.
    var playStart: CFTimeInterval? {
        guard let begin = windowView.layer.animation(forKey: Self.animationPrefix + "position")?.beginTime, begin > 0 else { return nil }
        return begin
    }

    private static let animationPrefix = "zoom."

    private func setModel(_ state: LayerState) {
        windowView.bounds = CGRect(origin: .zero, size: state.windowSize)
        windowView.center = state.windowCenter
        windowView.layer.cornerRadius = state.cornerRadius
        windowView.alpha = state.windowAlpha
        let center = CGPoint(x: state.windowSize.width / 2, y: state.windowSize.height / 2)
        if let content {
            content.transform = CGAffineTransform(scaleX: state.contentScale, y: state.contentScale)
            content.center = center
        }
        iconView.bounds = CGRect(x: 0, y: 0, width: state.iconSide, height: state.iconSide)
        iconView.center = center
        iconView.alpha = state.iconFace
    }

    private func removeAnimations() {
        for layer in [windowView.layer, iconView.layer, content?.layer].compactMap({ $0 }) {
            layer.removeAllAnimations()
        }
    }
}
