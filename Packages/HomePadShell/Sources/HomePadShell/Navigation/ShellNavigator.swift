import HomePadCore
import HomePadUI
import CoreGraphics
import Foundation
import Observation
import UIKit

/// App IDs the shell refers to by name. Every one may be missing, since other
/// modules register them and the shell must cope without them.
enum KnownAppID {
    static let settings = "settings"
    static let nowPlaying = "nowplaying"
    static let music = "music"
    static let mirror = "mirror"
    static let recipes = "recipes"
    /// The running timers. The timer pill opens it.
    static let timers = "timers"
    /// My Faces, the face gallery and the editor.
    static let faces = "faces"
    /// The face editor for the face on the wall, which holding the face opens (a redirect to Faces).
    static let editWallFace = "faces.editWallFace"
}

/// Where the user is: the face, the Home Screen or a full-screen app, plus the
/// transient panels drawn over them. All navigation goes through here, so
/// events, gestures and buttons behave the same.
@MainActor
@Observable
final class ShellNavigator {
    enum Screen: Equatable {
        case ambient
        case home
        case app(String)

        var appID: String? {
            if case .app(let id) = self { return id }
            return nil
        }
    }

    /// Panels that slide over the current screen.
    enum Panel: String, Equatable, CaseIterable {
        case controlCenter, people, appGrid
    }

    private(set) var screen: Screen = .ambient {
        didSet {
            if screen.appID != oldValue.appID { onOpenAppChange(screen.appID) }
            if let id = screen.appID, id != oldValue.appID { noteOpened(id) }
            // Going straight to another app keeps a picture of the one left, as a close does, for its next open.
            if let left = oldValue.appID, let id = screen.appID, left != id { zoomAnimator.keepPicture(of: left) }
            // An app closing, by any path, zooms into its icon.
            if let closed = oldValue.appID, screen.appID == nil { beginCloseZoom(of: closed) }
            // After any picture of the screen above, which shows what the app presented.
            showPresentations()
        }
    }
    /// Draws the app zoom on its overlay (`ZoomOverlay`), on a picture of the app.
    @ObservationIgnored let zoomAnimator = ZoomAnimator()
    /// The apps' hosts, which show and hide what each app presents (`showPresentations()`).
    @ObservationIgnored let appHosts = AppHostRegistry()
    /// True while the zoom shows a picture of the app in its place: the live app is laid out but not drawn.
    var hidesLiveApp = false {
        didSet { showPresentations() }
    }
    /// True while an app opens: it is not built until its window is full screen (`beginOpenZoom`).
    var defersLiveApp = false
    /// The icon whose app is zooming out of it or into it. It is hidden meanwhile, since the window is it.
    /// Icons read their own flag (`isIconHidden`), so a change updates only the icons it hides or shows.
    @ObservationIgnored var hiddenIconKey: String? {
        didSet { hiddenIcons.hide(hiddenIconKey) }
    }
    @ObservationIgnored private let hiddenIcons = ZoomHiddenIcons()
    /// The app whose close is zooming into its icon. It stays in the window, hidden under its picture,
    /// until the window lands, so taking it apart does not take the main thread from the zoom.
    var closingAppID: String?
    /// What apps open from in the window now, by id (`ZoomSource`): the app grid's icons, and the face's
    /// widgets and pills.
    @ObservationIgnored var windowSources: [String: ZoomSource] = [:]
    /// What apps open from on the Home Screen, by id: its icons, widgets and header pills. Reported apart
    /// from `windowSources` because the Home Screen has a host of its own, which preferences do not cross
    /// (`HomeScreenHost`).
    @ObservationIgnored var homeSources: [String: ZoomSource] = [:]
    /// What each app was opened from, by app ID. Kept per app, so an app closes into what opened it.
    @ObservationIgnored var zoomOrigins: [String: ZoomTarget] = [:]
    /// The app that opened with a fade rather than the zoom, and closes with one too (holding the face
    /// opens its editor this way). The shell fades its window in and out (`ShellContentView`).
    var fadingAppID: String?
    /// Where the last touch went down, in window coordinates, and when (`noteTouch(at:)`).
    @ObservationIgnored private var lastTouch: (point: CGPoint, time: Date)?
    /// The finger's speed a swipe up hands to the close that follows it (`AppZoomGeometry.dragVelocity`).
    @ObservationIgnored var closeVelocity: PoseVector?
    /// How the screen is lit, for the icon picture the zoom draws (dark icons at night).
    @ObservationIgnored var displayCondition: DisplayCondition = .active
    /// Reduce Motion is on: zooms cross fade instead. Kept up to date by the shell's content view.
    @ObservationIgnored var reduceMotion = false
    /// Tells a newer zoom from an older one whose completion arrives late.
    @ObservationIgnored var zoomToken = 0
    /// Told the app on screen whenever it changes, nil on the face and the Home
    /// Screen. The coordinator passes it on as `AppServices.visibleAppID`.
    @ObservationIgnored var onOpenAppChange: (String?) -> Void = { _ in }
    /// The app that opened the one on screen, such as Music for Now Playing.
    /// The app's back button and swipe down return to it. Home forgets it.
    private(set) var returnAppID: String?
    /// The app kept alive under the one on screen: the one that opened it, when
    /// the app on screen presents over its opener (Now Playing over Music). A
    /// swipe down shows it through, and going back finds it as it was.
    private(set) var appBehindID: String?
    /// Whether an opener may stay alive underneath. The coordinator says no
    /// while a camera is in use, so a hidden Mirror never keeps filming.
    @ObservationIgnored var mayKeepAppBehind: (String) -> Bool = { _ in true }
    /// The apps opened lately, the one on screen last. The shell keeps them suspended after they
    /// close (`SuspendableHost`), so they reopen where they were left, like iPadOS apps.
    private(set) var recentAppIDs: [String] = []
    /// How many closed apps stay suspended for their next open, unless memory runs low first.
    /// Four were dropped by an ordinary few minutes of use, and the next open of each started cold.
    static let suspendedAppLimit = 8
    /// The last person recognized at the screen, whose apps are the suspended ones.
    @ObservationIgnored private var suspendedAppsOwner: UUID?
    /// True while the app on screen is Faces, opened by holding the face, so
    /// closing it returns to the face. Every other app closes to the Home
    /// Screen, wherever it was opened from.
    private(set) var returnsToFace = false
    var panel: Panel?
    /// An app waiting behind the recognition gate.
    private(set) var gatedAppID: String?
    /// Face shown in ambient mode instead of the configured one (`.showFace` event).
    private(set) var faceOverride: String?
    var isEditingHomeScreen = false
    var isEditingControlCenter = false
    /// The Settings app opens on this pane next time it appears.
    var pendingSettingsPane: String?
    /// The Home Screen presents this sheet next time it appears.
    var pendingHomeSheet: HomeScreenSheet?
    /// The Home Screen opens Edit Stack or Edit Widget next time it appears (screenshots).
    var pendingFirstEdit: HomeFirstEdit?
    /// The Home Screen scrolls to this page next time it appears.
    var pendingHomePage: Int?
    /// The Home Screen page each person was last on (guests under "guest"), so
    /// closing an app returns to that page instead of the first one.
    /// Not observed: it is read only when the Home Screen is built, and a page swipe that rebuilt
    /// the shell's content for it moved the pages under the finger.
    @ObservationIgnored var lastHomePages: [String: Int] = [:]
    var isShowingOnboarding = false

    @ObservationIgnored let registry: ModuleRegistry
    @ObservationIgnored private let household: Household

    init(registry: ModuleRegistry, household: Household) {
        self.registry = registry
        self.household = household
        // The live app is hidden or not built, and its icon hidden, only while the zoom's picture stands in for it. A swipe Home
        // once left it hidden, so the next app opened invisible and the Home Screen under it took no touches.
        zoomAnimator.onEnd = { [weak self] in
            self?.hidesLiveApp = false
            self?.defersLiveApp = false
            self?.hiddenIconKey = nil
            self?.closingAppID = nil
        }
        // A suspended app's sheets and covers are dismissed (`SuspendableHostController`). Its picture still
        // shows them, so its next open grows a plain page in its color instead, which lands without a jump.
        appHosts.onDismissPresentations = { [weak self] appID in
            self?.zoomAnimator.forgetPicture(of: appID)
        }
        // Like iPadOS, suspended apps and their pictures go when memory runs low, not at a small fixed count.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropSuspendedApps() }
        }
    }

    /// What the app on screen presents (its sheets and full-screen covers) shows, unless the zoom's picture
    /// stands in for the app. UIKit draws presentations above the whole shell, zoom included, so while the
    /// picture of a swipe or a close (which shows them) moves, they are hidden, and every other app's are too.
    private func showPresentations() {
        appHosts.showPresentations(of: hidesLiveApp ? nil : screen.appID)
    }

    /// Lets every suspended app go, with the pictures kept for their opens. The app on screen stays.
    private func dropSuspendedApps() {
        recentAppIDs = [screen.appID, appBehindID].compactMap { $0 }
        zoomAnimator.forgetPictures()
    }

    var isAmbient: Bool { screen == .ambient }

    /// True while the icon recorded under `key` is hidden for its app's zoom (`hiddenIconKey`).
    /// A view that reads it updates only when this icon is hidden or shown again.
    func isIconHidden(_ key: String) -> Bool {
        hiddenIcons.isHidden(key)
    }

    /// The app on screen, if any.
    var openAppID: String? {
        if case .app(let id) = screen { return id }
        return nil
    }

    /// Opens an app full screen, behind the recognition gate when it is personal
    /// and nobody is recognized. A redirected ID opens the app it names ("cameras"
    /// opens Home on its cameras). Unknown IDs open a friendly "not available" screen.
    ///
    /// It grows out of what was touched to open it, however it was asked to
    /// open (`zoomOrigin(opening:as:)`), and closes back into it when the Home
    /// Screen has it (`zoomTarget(for:on:)`).
    /// - Parameters:
    ///   - fromFace: Holding the face opened Faces, which closes back to the face.
    ///   - fades: Fades the app in and out instead of zooming it, as holding the face opens its editor:
    ///     the whole face was held, not a part of it, so there is nothing to grow out of.
    func open(appID requestedID: String, fromFace: Bool = false, fades: Bool = false) {
        let appID = registry.followingRedirect(requestedID)
        let opener = openAppID
        if opener == nil {
            // Before the app grid or a panel closes, while what was touched is still drawn.
            zoomOrigins[appID] = fromFace ? nil : zoomOrigin(opening: requestedID, as: appID)
        }
        endTransientUI()
        if let app = registry.app(appID), app.requiresRecognizedMember, !household.isPersonalContentUnlocked {
            gatedAppID = appID
            if screen == .ambient { screen = .home }
            return
        }
        gatedAppID = nil
        if let opener, opener != appID {
            // Opening the app to go back to goes back, so two apps never bounce.
            returnAppID = appID == returnAppID ? nil : opener
            let presentsOver = registry.app(appID)?.presentsOverOpener == true
            appBehindID = returnAppID == opener && presentsOver && mayKeepAppBehind(opener) ? opener : nil
        } else if opener == nil {
            returnAppID = nil
            appBehindID = nil
            returnsToFace = fromFace
            fadingAppID = fades ? appID : nil
            if !fades { beginOpenZoom(of: appID, from: zoomOrigins[appID]) }
        }
        screen = .app(appID)
    }

    /// Records where a touch went down, from the shell's touch observer.
    func noteTouch(at point: CGPoint) {
        lastTouch = (point, Date())
    }

    /// What an app opening now opens from: the source a touch went down on a moment ago, or else the app's
    /// icon. Apps open from buttons, from events modules post and from redirects, so the touch, not the
    /// caller, says where.
    /// - Parameters:
    ///   - requestedID: The ID asked for, which a redirect may have turned into `appID`. Either one's icon counts.
    private func zoomOrigin(opening requestedID: String, as appID: String) -> ZoomTarget? {
        // Over the face or the Home Screen only the app grid reports sources. Control Center and People do not,
        // and what is under them was not touched.
        let sources: [String: ZoomSource]
        switch (panel, screen) {
        case (.appGrid, _), (nil, .ambient): sources = windowSources
        case (nil, .home): sources = homeSources
        default: return nil
        }
        var target: ZoomTarget?
        if let touch = lastTouch, Date().timeIntervalSince(touch.time) < 1 {
            target = Self.smallestSource(under: touch.point, in: sources)
        }
        if target == nil {
            let iconIDs = panel == .appGrid ? [ZoomSourceID.grid(requestedID), ZoomSourceID.grid(appID)] : [requestedID, appID]
            if let id = iconIDs.first(where: { sources[$0] != nil }), let icon = sources[id] {
                target = ZoomTarget(id: id, source: icon)
            }
        }
        if SwipeTrace.trace.isEnabled {
            let touched = lastTouch.map { "\(Int($0.point.x)),\(Int($0.point.y))" } ?? "-"
            let all = sources.map { "\($0.key) \(Self.describe($0.value.frame))" }.sorted().joined(separator: "; ")
            SwipeTrace.trace.log("zoom origin \(appID): \(target.map { "\($0.id) \(Self.describe($0.source.frame))" } ?? "none"), touch \(touched), sources: \(all)")
        }
        return target
    }

    /// A frame in whole points, for the trace.
    static func describe(_ frame: CGRect) -> String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }

    /// The smallest source under `point` (by where a touch counts, `hitFrame`), so a button inside a widget is
    /// not lost to the widget.
    static func smallestSource(under point: CGPoint, in sources: [String: ZoomSource]) -> ZoomTarget? {
        var smallest: ZoomTarget?
        var smallestArea = CGFloat.infinity
        for (id, source) in sources where source.hitFrame.contains(point) {
            let area = source.hitFrame.width * source.hitFrame.height
            if area < smallestArea {
                smallest = ZoomTarget(id: id, source: source)
                smallestArea = area
            }
        }
        return smallest
    }

    /// Opens what plays: `nowplaying`, which the Audio module redirects to
    /// Music with its full-screen player up, or plain Music without it.
    func openNowPlaying() {
        let handled = registry.app(KnownAppID.nowPlaying) != nil || registry.redirect(KnownAppID.nowPlaying) != nil
        open(appID: handled ? KnownAppID.nowPlaying : KnownAppID.music)
    }

    /// Closes the app on screen: back to the face when the face opened it,
    /// otherwise to the Home Screen.
    func closeApp() {
        returnsToFace ? goAmbient() : goHome()
    }

    /// Returns to the app that opened the one on screen, or closes it.
    func goBack() {
        guard let id = returnAppID, registry.app(id) != nil else { return closeApp() }
        endTransientUI()
        returnAppID = nil
        appBehindID = nil
        screen = .app(id)
    }

    /// Called when recognition succeeded while the gate was up.
    func completeGate() {
        guard let id = gatedAppID else { return }
        gatedAppID = nil
        beginOpenZoom(of: id, from: zoomTarget(for: id, on: screen))
        screen = .app(id)
    }

    func cancelGate() {
        gatedAppID = nil
    }

    /// Shows the gate for an app even if content is unlocked (screenshots).
    func presentGate(for appID: String) {
        endTransientUI()
        if screen == .ambient { screen = .home }
        gatedAppID = appID
    }

    /// Personal content relocked while a personal app was open: put the gate back up.
    func relockIfNeeded() {
        guard let id = openAppID, let app = registry.app(id), app.requiresRecognizedMember,
              !household.isPersonalContentUnlocked else { return }
        returnAppID = nil
        appBehindID = nil
        screen = .home
        gatedAppID = id
    }

    func goHome() {
        endTransientUI()
        returnAppID = nil
        appBehindID = nil
        returnsToFace = false
        screen = .home
    }

    func goAmbient() {
        endTransientUI()
        gatedAppID = nil
        returnAppID = nil
        appBehindID = nil
        returnsToFace = false
        screen = .ambient
    }

    /// Shows a specific face in ambient mode until another face is requested.
    func showFace(_ id: String) {
        faceOverride = id
        goAmbient()
    }

    /// Goes back to the usual face, the person's own or the household's,
    /// forgetting one asked for with `showFace`.
    func showDefaultFace() {
        faceOverride = nil
        goAmbient()
    }

    /// Opens Settings, optionally on one pane.
    func openSettings(pane: String? = nil) {
        pendingSettingsPane = pane
        open(appID: KnownAppID.settings)
    }

    /// Swipe up from the bottom edge: an app closes, back to where it was
    /// opened from like a tap on the home bar, the face goes Home, and the
    /// Home Screen opens (or closes) the app grid.
    func swipeUpFromBottom() {
        switch screen {
        case .app:
            closeApp()
        case .ambient:
            goHome()
        case .home:
            if isEditingHomeScreen {
                isEditingHomeScreen = false
            } else {
                panel = panel == .appGrid ? nil : .appGrid
            }
        }
    }

    func toggle(_ panel: Panel) {
        self.panel = self.panel == panel ? nil : panel
        if self.panel == .people && screen == .ambient { screen = .home }
    }

    /// Told the person at the screen whenever it changes. When someone else takes over, the suspended
    /// apps and their pictures are dropped, so no app keeps one person's state for another. Recognition
    /// lapsing and coming back, or a guest in between, keeps them: personal apps stay behind the
    /// recognition gate, and dropping them on every lapse made apps open fresh again and again.
    func noteMember(_ id: UUID?) {
        guard let id, id != suspendedAppsOwner else { return }
        if suspendedAppsOwner != nil { dropSuspendedApps() }
        suspendedAppsOwner = id
    }

    /// Puts `appID` last among the recent apps, dropping the oldest past the limit.
    private func noteOpened(_ appID: String) {
        recentAppIDs.removeAll { $0 == appID }
        recentAppIDs.append(appID)
        let limit = Self.suspendedAppLimit + 1
        if recentAppIDs.count > limit { recentAppIDs.removeFirst(recentAppIDs.count - limit) }
    }

    private func endTransientUI() {
        panel = nil
        isEditingHomeScreen = false
        isEditingControlCenter = false
    }
}
