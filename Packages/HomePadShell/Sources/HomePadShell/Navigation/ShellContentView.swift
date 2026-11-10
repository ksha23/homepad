import HomePadCore
import HomePadUI
import SwiftUI

/// Stacks the shell's layers, bottom to top: the face (also kept alive under a
/// Home Screen whose wallpaper frosts it), the Home Screen or app, system chrome (the timer and Now Playing pills, warnings), panels (Control
/// Center, People, app grid), the recognition gate, edge gestures, the sleeping
/// screen, and finally every module overlay.
struct ShellContentView: View {
    let coordinator: ShellCoordinator
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while the app on screen is swiped down and the app kept alive
    /// under it shows through.
    @State private var revealsAppBehind = false
    /// True while the app on top shows its running timers itself (cooking
    /// mode), so the timer pill steps aside.
    @State private var screenShowsTimers = false
    /// How bright the face's backdrop is, as the face reports it, for the
    /// Home Screen's widgets over the Face wallpaper.
    @State private var faceTone: BackdropTone?

    var body: some View {
        let navigator = coordinator.navigator
        let kiosk = coordinator.kiosk
        let faceIsScreen = navigator.screen == .ambient
        ZStack {
            if faceIsScreen || homeShowsFace {
                AmbientView()
                    // The face follows the camera even right after a touch, while
                    // apps and the Home Screen stay near until the touch times out.
                    // Under the Home Screen's frost it holds its near look: a
                    // wallpaper that changed layout as people moved around the
                    // room was distracting behind the icons.
                    .environment(\.proximity, faceIsScreen ? kiosk.faceProximity : .near)
                    // Under the blur the face draws only its picture or
                    // background, redrawn rarely (`isFrosted`). A still thumbnail
                    // drew differently, and switching to or from it showed through
                    // the blur as a glitch.
                    .environment(\.isFrosted, !faceIsScreen)
                    .allowsHitTesting(faceIsScreen)
                    .accessibilityHidden(!faceIsScreen)
                    .onPreferenceChange(BackdropToneKey.self) { faceTone = $0 }
                    .transition(.opacity)
                    // Always the bottom layer. Without an explicit order, a ZStack can
                    // draw a screen that is fading out below the face, so going back to
                    // the face cut instead of fading the Home Screen away.
                    .zIndex(-1)
            }
            if navigator.screen != .ambient {
                // Kept alive behind open apps so closing an app reveals the Home
                // Screen immediately instead of crossfading both through black.
                HomeScreenView(initialPage: coordinator.navigator.lastHomePages[household.activeMemberID?.uuidString ?? "guest"] ?? 0)
                    .id(household.activeMemberID)
                    .environment(\.frostedFaceTone, faceTone)
                    // Blurred and dimmed while an app is open over it, with its icons sitting back a little.
                    .modifier(HomeRecessionEffect(receded: navigator.screen.appID != nil))
                    .allowsHitTesting(navigator.screen == .home)
                    .accessibilityHidden(navigator.screen != .home)
                    .transition(.opacity)
            }
            let topAppID = navigator.screen.appID
            let layers = appLayers(top: topAppID)
            if !layers.isEmpty {
                // Every app opened lately, each in a host of its own, keyed by app. Only the app on top, and
                // the one kept alive under it (Now Playing over Music), is in the window. The others are
                // suspended there, so they reopen where they were left, with their page and scroll position.
                ZStack {
                    ForEach(layers, id: \.self) { appID in
                        let isTop = appID == topAppID
                        let isBehind = appID == navigator.appBehindID && !isTop
                        let isClosing = appID == navigator.closingAppID && !isTop
                        let hasAppBehind = isTop && navigator.appBehindID != nil
                        // An opening app joins the window once its zoom is full screen (`beginOpenZoom`). A closing
                        // one leaves it once its window has landed, hidden under its picture until then.
                        SuspendableHost(appID: appID, hosts: navigator.appHosts,
                                        isActive: isTop ? !navigator.defersLiveApp : isBehind || isClosing,
                                        isCovered: !isTop, inputs: hasAppBehind) {
                            AppContainerView(appID: appID, hasAppBehind: hasAppBehind) { pulled in
                                revealsAppBehind = pulled
                            }
                        }
                        .equatable()
                        // The host covers the window and passes the screen margin in as its safe area, so the
                        // app's page color fills the margin. Inside the margin the host had no margin to fill.
                        .ignoresSafeArea()
                        // The app behind is hidden while covered, so it costs nothing to draw.
                        .opacity(isTop || (isBehind && revealsAppBehind) ? 1 : 0)
                        // A closing app is gone at once, under its picture. Fading with the screen change, it
                        // showed full screen behind its shrinking window. An app that opened with a fade
                        // (`fadingAppID`, the face's editor) has no picture over it, so it fades in and out.
                        .animation(appID == navigator.fadingAppID ? Theme.Motion.screen : nil, value: isTop)
                        .allowsHitTesting(isTop)
                        .accessibilityHidden(!isTop)
                        // An app over its opener fades in over it, as does one opened with a fade. An app
                        // opened from its icon appears at once: the zoom (`ZoomOverlay`) has drawn it until then.
                        .transition(navigator.appBehindID != nil || appID == navigator.fadingAppID ? .opacity : .identity)
                        .zIndex(isTop ? 1 : 0)
                    }
                    // Part of the window, so it shrinks and moves with it like the iPadOS home indicator.
                    // Covers the app presents draw their own (`coverHomeBar()`), with the same actions.
                    if topAppID != nil, navigator.gatedAppID == nil {
                        HomeBar(actions: navigator.homeBarActions).zIndex(2)
                    }
                }
                // Laid out but not drawn while the zoom shows a picture of it in its place.
                .opacity(navigator.hidesLiveApp ? 0 : 1)
                .animation(nil, value: navigator.hidesLiveApp)
                .onChange(of: topAppID) { revealsAppBehind = false }
            }
            // The app zoom: a picture of the app growing out of its icon or shrinking back into it.
            ZoomOverlay(animator: navigator.zoomAnimator)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            SystemChromeLayer(screenShowsTimers: screenShowsTimers)
            // In the strip above the screen margin, where the status bar would be.
            BatteryIndicator(health: kiosk.health)
                .nightModeAware()
                .padding(.top, 6)
                .padding(.trailing, Theme.Spacing.screenMargin.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()
            PanelLayer()
            if let appID = navigator.gatedAppID {
                RecognitionGateView(appID: appID)
                    .transition(.opacity)
                    .zIndex(1)
            }
            EdgeGestureLayer(
                onAssistant: coordinator.invokeAssistant,
                onControlCenter: { navigator.toggle(.controlCenter) }
            )
            if kiosk.condition == .sleeping {
                SleepingView()
                    .transition(.opacity)
                    .zIndex(2)
            }
            ForEach(registry.overlays) { overlay in
                overlay.makeView()
                    .environment(\.isOnFace, navigator.screen == .ambient)
            }
            .zIndex(3)
        }
        .onChange(of: reduceMotion, initial: true) { _, value in navigator.reduceMotion = value }
        .onChange(of: kiosk.condition, initial: true) { _, value in navigator.displayCondition = value }
        .onPreferenceChange(ZoomSourcesKey.self) { navigator.windowSources = $0 }
        .environment(coordinator)
        .environment(navigator)
        .environment(kiosk)
        .environment(coordinator.homeLayouts)
        .environment(coordinator.wallpapers)
        .environment(\.displayCondition, kiosk.condition)
        .environment(\.proximity, kiosk.proximity)
        .textSize(services.settings[ShellSettings.textSize])
        .preferredColorScheme(colorScheme)
        // UI tests that tap an app's close button turn it on with a launch argument.
        .environment(\.showsAppCloseButton, services.settings[ShellSettings.showsCloseButton]
            || UserDefaults.standard.bool(forKey: "HomePadShowCloseButtons"))
        .background(TouchObserver(onTouch: kiosk.noteTouch, at: { [navigator] point in navigator.noteTouch(at: point) }))
        .defersSystemGestures(on: .vertical)
        // Hide the system home indicator so only the shell's cleanly positioned
        // swipe bar is visible, and to prevent burn-in on the always-on face.
        .persistentSystemOverlays(.hidden)
        .animation(Theme.Motion.screen, value: navigator.screen)
        .animation(Theme.Motion.settle, value: navigator.panel)
        .animation(Theme.Motion.screen, value: navigator.gatedAppID)
        .animation(Theme.Motion.screen, value: kiosk.condition)
        // A person recognized (or leaving) changes the layout, wallpaper, greeting
        // and personal content at once, which snapped without an animation.
        .animation(Theme.Motion.screen, value: household.activeMemberID)
        .animation(Theme.Motion.screen, value: household.isPersonalContentUnlocked)
        .fullScreenCover(isPresented: Binding(
            get: { navigator.isShowingOnboarding },
            set: { if !$0 { coordinator.finishOnboarding() } }
        )) {
            OnboardingView()
                .environment(coordinator)
                .environment(navigator)
                .modifier(ForcedLandscape(addsScreenMargin: false))
                // A cover is its own presentation, so it asks for the same scheme.
                .preferredColorScheme(colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: coordinator.sceneDidBecomeActive()
            case .background: coordinator.sceneDidEnterBackground()
            default: break
            }
        }
        .onChange(of: household.isPersonalContentUnlocked) { _, unlocked in
            if unlocked { navigator.completeGate() } else { navigator.relockIfNeeded() }
        }
        // Suspended apps hold the state of whoever used them, so another person starts them fresh.
        .onChange(of: household.activeMemberID, initial: true) { _, id in navigator.noteMember(id) }
    }

    /// The appearance setting, but dark at night: night mode tints the screen
    /// red, and a white page would turn into a bright red one. Nil follows the iPad.
    private var colorScheme: ColorScheme? {
        coordinator.kiosk.condition == .night ? .dark : services.settings[ShellSettings.appearance].colorScheme
    }

    /// The Home Screen (or an app over it) is active and its wallpaper is the frosted face.
    private var homeShowsFace: Bool {
        coordinator.navigator.screen != .ambient
            && services.settings[ShellSettings.wallpaper(for: household.activeMemberID)] == .face
    }

    /// The app on screen, with the app kept alive under it first.
    /// The apps opened lately, the suspended ones first, then the app kept alive under the one on top, then the top.
    private func appLayers(top id: String?) -> [String] {
        let navigator = coordinator.navigator
        let behind = navigator.appBehindID.flatMap { $0 == id ? nil : $0 }
        let front = [behind, id].compactMap { $0 }
        return navigator.recentAppIDs.filter { !front.contains($0) } + front
    }
}
