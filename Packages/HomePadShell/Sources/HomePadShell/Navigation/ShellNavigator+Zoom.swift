import HomePadCore
import HomePadUI
import SwiftUI

/// The app zoom: an app growing out of its icon and shrinking back into it.
///
/// It runs on a picture of the app, not the live app (`ZoomAnimator`). Closing
/// takes a picture of the screen as it is, so the window that shrinks is exactly
/// what was shown, margin and home bar included. Opening grows the picture the
/// app had when it was last closed, or a plain page in its color the first
/// time, then hands over to the live app. A swipe up drives the picture by
/// hand. The icon itself is hidden while its app is in flight, since the window
/// is it, and shows again the moment the window lands on it.
extension ShellNavigator {
    /// Starts a close: the window shrinks into what the app was opened from (`zoomTarget(for:on:)`), or into a
    /// stand-in at the screen's center that fades when there is nothing to land on.
    func beginCloseZoom(of appID: String) {
        // An app that faded in fades out, unless a swipe up already holds its window.
        if appID == fadingAppID, !zoomAnimator.isActive {
            fadeOut(appID)
            return
        }
        guard !reduceMotion else { return }
        let animator = zoomAnimator
        let geometry = AppZoomGeometry.standard
        let screen = animator.screen
        guard !screen.isEmpty else { return }
        ZoomSignposts.note(.close)
        let target = zoomTarget(for: appID, on: self.screen)
        let landing = target?.source.frame ?? geometry.fallbackIcon(screen: screen)
        if !animator.isActive {
            // The screen still shows the app: SwiftUI takes it away only after this.
            guard let picture = animator.snapshotScreen() else { return }
            beginZoom(picture: picture, of: appID, isAppPicture: true, pose: .full, target: target)
        }
        zoomToken += 1
        let token = zoomToken
        // The frame rate the main thread keeps through the close, in Documents/fps-trace.txt.
        FPSMonitor.shared.start(name: "AppZoom.close \(appID)", duration: 0.8)
        hiddenIconKey = target?.hiddenKey
        // Suspended only once the window lands (`ZoomAnimator.onEnd`), so its teardown never takes a frame from the zoom.
        // An app closed before its open finished was never built, and stays that way.
        closingAppID = defersLiveApp ? nil : appID
        let velocity = closeVelocity
        closeVelocity = nil
        animator.animate(to: geometry.iconPose(icon: landing, screen: screen), spring: HomeSwipePolicy.closeSpring,
                         fingerVelocity: velocity, fadesOut: target == nil) { [weak self] in
            guard let self, token == self.zoomToken else { return }
            // The icon shows again first. The picture over it, which looks the same, goes a frame later.
            self.hiddenIconKey = nil
            self.zoomAnimator.end(afterFrames: 1, keepingPictureFor: appID) { [weak self] in token == self?.zoomToken }
        }
    }

    /// Starts an open: the window grows out of `target`, what the app was opened from, or out of a stand-in
    /// at the screen's center when there is none.
    /// An app opened lately is still alive, suspended: it rejoins the window at once, hidden under the zoom,
    /// so it wakes up while the window grows and is live and current the moment it lands. An app that has
    /// to be built from nothing waits until the window is full screen, like an iPadOS launch, since building
    /// it takes the main thread for a moment.
    func beginOpenZoom(of appID: String, from target: ZoomTarget?) {
        guard !reduceMotion else { return }
        let animator = zoomAnimator
        let geometry = AppZoomGeometry.standard
        let screen = animator.screen
        guard !screen.isEmpty else { return }
        ZoomSignposts.note(.open)
        let target = target.flatMap { geometry.target(icon: $0.source.frame, screen: screen) == nil ? nil : $0 }
        let start = target?.source.frame ?? geometry.fallbackIcon(screen: screen)
        zoomToken += 1
        let token = zoomToken
        // The frame rate the main thread keeps through the open, in Documents/fps-trace.txt.
        FPSMonitor.shared.start(name: "AppZoom.open \(appID)", duration: 0.8)
        // Opened again while its close is still in flight: the window turns around from where it is, with its
        // picture, as on iPadOS. Starting over threw that picture away for a plain page.
        if !(animator.isActive && animator.pictureAppID == appID) {
            let picture = animator.picture(forOpening: appID)
            beginZoom(picture: picture.view, of: appID, isAppPicture: picture.isAppPicture,
                      pose: geometry.iconPose(icon: start, screen: screen), target: target)
        }
        hiddenIconKey = target?.hiddenKey
        let isSuspended = recentAppIDs.contains(appID)
        defersLiveApp = !isSuspended
        hidesLiveApp = isSuspended
        animator.animate(to: .full, spring: HomeSwipePolicy.openSpring) { [weak self] in
            guard let self, token == self.zoomToken else { return }
            self.defersLiveApp = false
            self.hidesLiveApp = false
            self.hiddenIconKey = nil
            // Once the app is drawn under it: a frame for an app already in the window, three for one built now.
            // A real picture goes back for the next open.
            self.zoomAnimator.end(afterFrames: isSuspended ? 1 : 3, keepingPictureFor: appID) { [weak self] in
                token == self?.zoomToken
            }
        }
    }

    /// Follows the finger of a swipe up: the window's bottom edge stays under it. The first move
    /// takes a picture of the app, which the finger then moves while the live app is hidden. Its
    /// icon is hidden from the start, since the window is it.
    func trackZoom(translation: CGSize) {
        guard let id = screen.appID, !reduceMotion else { return }
        let animator = zoomAnimator
        let geometry = AppZoomGeometry.standard
        let screen = animator.screen
        guard !screen.isEmpty else { return }
        if !animator.isActive {
            guard let picture = animator.snapshotScreen() else { return }
            let target = zoomTarget(for: id, on: returnsToFace ? .ambient : .home)
            beginZoom(picture: picture, of: id, isAppPicture: true, pose: .full, target: target)
            hidesLiveApp = true
            hiddenIconKey = target?.hiddenKey
            ZoomSignposts.note(.swipe)
        }
        zoomToken += 1
        animator.set(geometry.dragPose(translation: translation, screen: screen))
    }

    /// Lets go below the threshold: the window springs back to full screen with the finger's speed,
    /// and the live app and its icon show again.
    func cancelZoom(fingerVelocity: PoseVector) {
        let animator = zoomAnimator
        guard animator.isActive else { return }
        ZoomSignposts.note(.springBack)
        zoomToken += 1
        let token = zoomToken
        animator.animate(to: .full, spring: HomeSwipePolicy.closeSpring, fingerVelocity: fingerVelocity) { [weak self] in
            guard let self, token == self.zoomToken else { return }
            self.hidesLiveApp = false
            self.hiddenIconKey = nil
            self.zoomAnimator.end(afterFrames: 2, keepingPictureFor: self.zoomAnimator.pictureAppID) { [weak self] in
                token == self?.zoomToken
            }
        }
    }

    /// Fades a closing app out over the screen it closes to. It stays in the window until its fade has
    /// finished, then is suspended like a zoomed app once its window lands.
    private func fadeOut(_ appID: String) {
        closingAppID = appID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Motion.screenDuration))
            guard let self else { return }
            if self.closingAppID == appID { self.closingAppID = nil }
            if self.fadingAppID == appID, self.openAppID != appID { self.fadingAppID = nil }
        }
    }

    /// Where `appID` lands on `place` as it closes, or nil for the stand-in at the screen's center.
    ///
    /// Apps close to the Home Screen, which stays laid out behind an open app, so what opened the app is
    /// found where it is now, even if it moved or the iPad turned. An app opened from the face has no
    /// source there unless it was a pill, which the Home Screen's header has too. Otherwise the app lands
    /// on its own icon when the Home Screen's page has it, and on the stand-in when it does not.
    ///
    /// Faces, opened by holding the face, closes back to the face onto the stand-in, as it opened.
    func zoomTarget(for appID: String, on place: Screen) -> ZoomTarget? {
        let origin = zoomOrigins[appID]
        var found: ZoomTarget?
        if place == .home {
            let id = origin.flatMap { homeSources[$0.id] == nil ? nil : $0.id } ?? appID
            found = homeSources[id].map { ZoomTarget(id: id, source: $0) }
        }
        // Only a source wholly on screen: one on another page of the Home Screen is not worth landing on.
        let onScreen = found.flatMap { AppZoomGeometry.standard.target(icon: $0.source.frame, screen: zoomAnimator.screen) == nil ? nil : $0 }
        if SwipeTrace.trace.isEnabled {
            let landing = onScreen.map { "\($0.id) \(Self.describe($0.source.frame))" } ?? "the stand-in"
            SwipeTrace.trace.log("zoom target \(appID) on \(place): \(landing), origin \(origin?.id ?? "none")")
        }
        return onScreen
    }

    /// Starts the window on `target`, or on the stand-in at the screen's center. An icon's window turns into
    /// the icon's picture, which hides the icon meanwhile. A widget's or a pill's window takes its shape and
    /// corners and dissolves into it, which stays in view under it.
    private func beginZoom(picture: UIView, of appID: String, isAppPicture: Bool, pose: ZoomPose, target: ZoomTarget?) {
        let frame = target?.source.frame ?? AppZoomGeometry.standard.fallbackIcon(screen: zoomAnimator.screen)
        let dissolves = target.map { $0.source.shape != .icon } ?? false
        zoomAnimator.begin(picture: picture, of: appID, isAppPicture: isAppPicture, pose: pose, icon: frame,
                           face: dissolves ? nil : iconPicture(appID),
                           cornerRadius: target?.source.cornerRadius, dissolves: dissolves)
    }

    /// The app's icon picture, which the window turns into.
    private func iconPicture(_ appID: String) -> UIImage? {
        guard let app = registry.app(appID) else { return nil }
        return ZoomIconPictures.picture(ZoomIconFace(systemImage: app.systemImage, tint: app.tint), condition: displayCondition)
    }
}

/// What an app zooms out of and back into: a source on screen (`ZoomSource`) and its id.
struct ZoomTarget: Equatable {
    var id: String
    var source: ZoomSource

    /// The id to hide while the app is in flight: an icon's, since the window is it. A widget or a pill stays
    /// in view for the window to melt into.
    var hiddenKey: String? {
        source.shape == .icon ? id : nil
    }
}
