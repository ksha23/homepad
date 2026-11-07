import HomePadUI
import SwiftUI
import UIKit

/// Runs the app zoom on the overlay (`ZoomOverlayView`): a picture of the app
/// as one window, set straight from the finger or moved by a spring. A spring is
/// worked out frame by frame up front and played by Core Animation, so the
/// window moves at the screen's full rate even while the main thread is busy
/// with the screen change it goes with. The live app is hidden meanwhile, so
/// nothing in it is drawn again for the zoom, and whatever the app draws in the
/// screen's margin is in the picture and moves with the rest of the window, like iPadOS.
@MainActor
final class ZoomAnimator: NSObject {
    private weak var overlay: ZoomOverlayView?
    private let geometry = AppZoomGeometry.standard

    /// The pose the window rests at, or was last set to by a finger.
    private var restingPose = ZoomPose.full
    /// The icon the window heads for or comes from, in window coordinates.
    private var icon: CGRect = .zero
    /// The target's corner radius when it is not an app icon (a widget).
    private var targetCornerRadius: CGFloat?
    /// The window fades as it takes the target's shape (`begin`).
    private var dissolves = false
    private var run: Run?
    private var runCount = 0
    /// A picture of each app as it was last shown, newest last, for its next open.
    private var pictures: [(appID: String, view: UIView)] = []

    /// How many poses a second a spring is worked out at: the screen's top rate.
    private static let framesPerSecond = 120.0

    /// One spring from a pose toward a target, playing on the overlay.
    private struct Run {
        var id: Int
        var from: PoseVector
        var to: PoseVector
        var initialVelocity: PoseVector
        var spring: Spring
        /// When it was asked for. Core Animation starts it on the next frame it draws, which the overlay
        /// reports once it has (`playStart`), so a busy main thread delays the spring rather than skipping it.
        var requested: CFTimeInterval
    }

    /// The pose drawn now: where the spring playing has the window, or where it rests.
    var pose: ZoomPose {
        guard let run else { return restingPose }
        return sample(run, at: CACurrentMediaTime()).value.pose
    }

    /// True while the overlay shows the app's picture.
    var isActive: Bool { pictureShown }
    private var pictureShown = false
    /// The app the overlay's picture shows, while it shows one.
    private(set) var pictureAppID: String?
    /// True while that picture is of the app as it was just shown, not a kept one or a plain page.
    private var showsAppPicture = false

    /// True while a finger holds the window: the picture is up and no spring moves it.
    var isHeld: Bool { pictureShown && run == nil }

    /// Told whenever the picture goes, whichever zoom put it up. The live app it stood in for must show again then.
    var onEnd: @MainActor () -> Void = {}

    /// The window's bounds, which every pose is worked out in.
    var screen: CGRect { overlay?.bounds ?? .zero }

    func attach(_ view: ZoomOverlayView) {
        overlay = view
    }

    /// A picture of the screen exactly as it is shown now: the open app with its margin and home bar.
    func snapshotScreen() -> UIView? {
        overlay?.window?.snapshotView(afterScreenUpdates: false)
    }

    /// The app's picture from when it was last shown, or a plain page in the app's own color when there is none.
    /// `isAppPicture` tells them apart.
    func picture(forOpening appID: String) -> (view: UIView, isAppPicture: Bool) {
        if let index = pictures.lastIndex(where: { $0.appID == appID }) {
            let picture = pictures.remove(at: index).view
            return (picture, true)
        }
        let page = UIView(frame: screen)
        page.backgroundColor = UIColor(Color.screenBackground)
        return (page, false)
    }

    /// Shows `picture` of `appID` as the window at `pose`, heading for or coming from `icon`, with `face` as its icon
    /// picture. `isAppPicture` is true for a real picture of the app (a close's or a swipe's, or one kept from before),
    /// false for a plain launch page. A real one goes back to the kept pictures whenever its zoom ends, even when
    /// another zoom cuts it short: with opens and closes a moment apart, zooms rarely finish, and pictures lost
    /// that way ran out until every open was a plain page.
    /// `cornerRadius` is the target's, an icon's by default. `dissolves` fades the window as it takes the target's
    /// shape, so it melts into what is drawn there (a widget) instead of turning into an icon picture.
    func begin(picture: UIView, of appID: String, isAppPicture: Bool, pose: ZoomPose, icon: CGRect, face: UIImage?,
               cornerRadius: CGFloat? = nil, dissolves: Bool = false) {
        guard let overlay else { return }
        // The zoom cut short leaves its app's picture for that app's next open.
        if pictureShown, showsAppPicture, let outgoing = pictureAppID, outgoing != appID, let kept = overlay.unload() {
            keep(kept, for: outgoing)
        }
        run = nil
        self.icon = icon
        targetCornerRadius = cornerRadius
        self.dissolves = dissolves
        overlay.load(picture, icon: face)
        pictureShown = true
        pictureAppID = appID
        showsAppPicture = isAppPicture
        show(pose)
    }

    /// Moves the window straight to `pose`, as a finger does. The speed is taken from the finger when it lets go.
    func set(_ pose: ZoomPose) {
        guard pictureShown else { return }
        run = nil
        show(pose)
    }

    /// Springs the window from where it is to `target`. `fingerVelocity` (scale and offset per second) carries the
    /// finger's speed into the spring, or else it keeps the speed of a spring it takes over. `fadesOut` fades the
    /// window as it arrives, for a stand-in with no real icon.
    func animate(to target: ZoomPose, spring: Spring, fingerVelocity: PoseVector? = nil, fadesOut: Bool = false,
                 completion: @escaping () -> Void) {
        guard pictureShown, let overlay, !screen.isEmpty else { return completion() }
        let now = CACurrentMediaTime()
        let current = run.map { sample($0, at: now) }
        let from = current?.value ?? PoseVector(restingPose)
        let to = PoseVector(target)
        let initialVelocity = fingerVelocity ?? current?.velocity ?? .zero
        let move = to - from
        let whole = max(0.0001, move.magnitudeSquared.squareRoot())
        let frameTime = 1 / Self.framesPerSecond
        let settling = max(spring.settlingDuration, 2 * frameTime)
        // The spring's own maths runs from zero toward the whole move, so add where it started.
        var values = stride(from: 0, through: settling, by: frameTime).map { time in
            from + spring.value(target: move, initialVelocity: initialVelocity, time: time)
        }
        // The spring's maths settles far below what anyone can see. The window arrives once it stays within half a
        // point of its target, and the zoom ends there, so what follows an arrival is not held back by an invisible
        // tail: a close's picture is kept for the next open, and the icon shows again, as soon as it has landed.
        let lastMoving = values.lastIndex { distanceInPoints($0, to) > 0.5 } ?? 0
        values = Array(values.prefix(lastMoving + 1)) + [to]
        let duration = Double(values.count - 1) * frameTime
        // A window flying to or from a widget turns over the last (or first) part of the way, by distance. One
        // springing back to full screen from a finger never goes to the widget, so it stays the app's picture.
        let widget = PoseVector(geometry.iconPose(icon: icon, screen: screen))
        let flies = distanceInPoints(to, widget) < 1 || distanceInPoints(from, widget) < 1
        let span = max(distanceInPoints(from, widget), distanceInPoints(to, widget), 1)
        let states = values.map { value in
            var state = self.state(at: value.pose, in: overlay,
                                   closeness: flies ? min(1, max(0, 1 - distanceInPoints(value, widget) / span)) : 0)
            if fadesOut {
                state.windowAlpha = min(1, CGFloat((value - to).magnitudeSquared.squareRoot() / whole) * 4)
            }
            return state
        }
        runCount += 1
        let id = runCount
        run = Run(id: id, from: from, to: to, initialVelocity: initialVelocity, spring: spring, requested: now)
        overlay.play(states, duration: duration) { [weak self] in
            // Also called when a finger or another spring takes the window over, which is not an arrival.
            guard let self, self.run?.id == id else { return }
            ZoomSignposts.note(.land)
            self.run = nil
            self.restingPose = target
            completion()
        }
    }

    /// Takes the picture away once the screen has drawn `frames` more frames, so whatever replaces it is on
    /// screen first, unless `stillCurrent` says a newer zoom has started meanwhile.
    func end(afterFrames frames: Int, keepingPictureFor appID: String? = nil, if stillCurrent: @escaping () -> Bool) {
        Task { @MainActor in
            for _ in 0..<frames { await nextFrame() }
            if stillCurrent() { end(keepingPictureFor: appID) }
        }
    }

    private func nextFrame() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let waiter = FrameWaiter(done)
            let link = CADisplayLink(target: waiter, selector: #selector(FrameWaiter.fire))
            waiter.link = link
            link.add(to: .main, forMode: .common)
        }
    }

    /// Takes the picture away. A real picture of the app is kept for `appID`'s next open, when given.
    func end(keepingPictureFor appID: String? = nil) {
        let keepsPicture = showsAppPicture
        run = nil
        pictureShown = false
        pictureAppID = nil
        showsAppPicture = false
        onEnd()
        guard let picture = overlay?.unload() else { return }
        if let appID, keepsPicture { keep(picture, for: appID) }
    }

    /// Keeps a picture of `appID` as the screen shows it now, for its next open: going straight from it to
    /// another app has no close to take one.
    func keepPicture(of appID: String) {
        guard let picture = snapshotScreen() else { return }
        keep(picture, for: appID)
    }

    /// How many apps' pictures are kept. More than the apps kept suspended, since a picture costs far less
    /// than a whole app, and an app that has to start again still grows out of its icon as it was left.
    private static let pictureLimit = 12

    private func keep(_ picture: UIView, for appID: String) {
        pictures.removeAll { $0.appID == appID }
        pictures.append((appID, picture))
        if pictures.count > Self.pictureLimit { pictures.removeFirst() }
    }

    /// Drops every app's picture, so none shows one person's screen to another.
    func forgetPictures() {
        pictures.removeAll()
    }

    /// Drops `appID`'s picture, when the app no longer looks like it. Its next open grows a plain page.
    func forgetPicture(of appID: String) {
        pictures.removeAll { $0.appID == appID }
    }

    /// Where `run` has the window at `time`, and how fast it is moving: the spring at the time since Core
    /// Animation started it, or since it was asked for until then.
    private func sample(_ run: Run, at time: CFTimeInterval) -> (value: PoseVector, velocity: PoseVector) {
        let start = overlay?.playStart ?? run.requested
        let elapsed = min(max(0, time - start), run.spring.settlingDuration)
        let move = run.to - run.from
        let value = run.from + run.spring.value(target: move, initialVelocity: run.initialVelocity, time: elapsed)
        let velocity = run.spring.velocity(target: move, initialVelocity: run.initialVelocity, time: elapsed)
        return (value, velocity)
    }

    /// How far apart two poses are on screen, in points: the change in size across the screen plus the move.
    private func distanceInPoints(_ a: PoseVector, _ b: PoseVector) -> CGFloat {
        let difference = a - b
        return abs(difference.first) * max(screen.width, screen.height)
            + hypot(difference.second.first, difference.second.second)
    }

    /// The window's look at `pose`, heading for or coming from `icon`. Into a widget, `closeness` is the share of
    /// its flight it has come.
    private func look(at pose: ZoomPose, closeness: CGFloat) -> AppZoomGeometry.Look {
        geometry.look(at: pose, screen: screen, target: icon.size,
                      cornerRadius: targetCornerRadius ?? Theme.Radius.icon(icon.width),
                      widgetTurn: dissolves ? geometry.widgetTurn(closeness: closeness) : nil)
    }

    /// The overlay's layers at `pose`. A dissolving window fades out as it takes the target's shape.
    private func state(at pose: ZoomPose, in overlay: ZoomOverlayView, closeness: CGFloat) -> ZoomOverlayView.LayerState {
        let look = look(at: pose, closeness: closeness)
        var state = overlay.state(pose: pose, look: look)
        if dissolves { state.windowAlpha = 1 - look.iconFace }
        return state
    }

    /// Puts the window at `pose` at once. A finger holds it as the app's picture, so it turns into a widget
    /// only where it sits on it, which is where an open from a widget starts.
    private func show(_ pose: ZoomPose) {
        restingPose = pose
        guard let overlay, !screen.isEmpty else { return }
        let onTarget = distanceInPoints(PoseVector(pose), PoseVector(geometry.iconPose(icon: icon, screen: screen))) < 1
        overlay.apply(state(at: pose, in: overlay, closeness: onTarget ? 1 : 0))
    }
}

/// Resumes a waiting task on the next screen refresh, once.
private final class FrameWaiter: NSObject {
    private var done: CheckedContinuation<Void, Never>?
    var link: CADisplayLink?

    init(_ done: CheckedContinuation<Void, Never>) {
        self.done = done
    }

    @objc func fire() {
        link?.invalidate()
        link = nil
        done?.resume()
        done = nil
    }
}
