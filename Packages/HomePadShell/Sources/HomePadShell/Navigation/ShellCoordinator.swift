import Foundation
import HomePadCore
import Observation

/// Owns the shell's long-lived objects (navigator, kiosk controller, layout
/// stores) and connects them: bus events become navigation and wake-ups,
/// interaction timeouts return to the face, and debug launch arguments apply.
@MainActor
@Observable
final class ShellCoordinator {
    let navigator: ShellNavigator
    let kiosk: KioskController
    let homeLayouts: HomeScreenLayoutStore
    let wallpapers: WallpaperPhotoStore
    let launchOptions: LaunchOptions

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    /// HomePad is on screen, for background work's conditions.
    @ObservationIgnored private var isInForeground = true

    init(
        services: AppServices, registry: ModuleRegistry,
        launchOptions: LaunchOptions = .current(), kioskDependencies: KioskDependencies? = nil
    ) {
        self.services = services
        self.launchOptions = launchOptions
        navigator = ShellNavigator(registry: registry, household: services.household)
        kiosk = KioskController(services: services, dependencies: kioskDependencies ?? .live())
        homeLayouts = HomeScreenLayoutStore(settings: services.settings, registry: registry)
        wallpapers = WallpaperPhotoStore()
        // An app holding a camera is not kept alive under Now Playing, so the
        // camera turns off while it is out of sight.
        navigator.mayKeepAppBehind = { [capture = services.capture] _ in capture.foregroundClaim == nil }
        // The assistant reads which app is on screen, to know what "this" is.
        navigator.onOpenAppChange = { [weak services] in services?.visibleAppID = $0 }
    }

    /// Starts the kiosk and event routing. Safe to call more than once.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        kiosk.onInteractionEnded = { [weak navigator] in navigator?.goAmbient() }
        kiosk.onTick = { [weak self] in
            self?.publishKioskStatus()
            self?.reportToBackgroundWork()
        }
        applyLaunchOptions()
        if BackgroundWorkHost.hostsBackgroundWork { services.backgroundWork.start() }
        kiosk.start()
        let stream = services.events.stream()
        eventTask = Task { [weak self] in
            for await event in stream {
                self?.route(event)
            }
        }
        // iPads set up before setup asked for permissions get asked once now,
        // after the modules have subscribed to the bus.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.requestSensingPermissionsOnce()
        }
    }

    /// The app came to the foreground.
    func sceneDidBecomeActive() {
        isInForeground = true
        kiosk.start()
    }

    /// The app went to the background: give brightness and Auto-Lock back,
    /// and ask iOS to launch HomePad for background work while it is away.
    func sceneDidEnterBackground() {
        kiosk.stop()
        isInForeground = false
        reportToBackgroundWork()
        if BackgroundWorkHost.hostsBackgroundWork { services.backgroundWork.scheduleSystemLaunches() }
    }

    /// Tells background work what the iPad is doing, once a kiosk tick, so a
    /// due task starts while nobody needs the screen.
    private func reportToBackgroundWork() {
        services.backgroundWork.update(BackgroundWorkHost.environment(
            kiosk: kiosk, navigator: navigator, isForeground: isInForeground, now: Date()
        ))
    }

    /// Swipe down from the top (left or center): talk to the assistant.
    func invokeAssistant() {
        services.assistant.startListening()
        services.events.post(.invokeAssistant(prompt: nil))
    }

    /// Onboarding finished or was skipped.
    func finishOnboarding() {
        services.settings[ShellSettings.onboardingCompleted] = true
        navigator.isShowingOnboarding = false
        requestSensingPermissionsOnce()
    }

    /// Asks for camera, microphone and speech recognition access once: from the
    /// privacy step of setup, which explains them, or after setup was skipped.
    /// Never during setup before that step.
    func requestSensingPermissions() {
        services.settings[ShellSettings.askedSensingPermissions] = true
        services.events.post(.requestSensingPermissions)
    }

    private func requestSensingPermissionsOnce() {
        let settings = services.settings
        guard settings[ShellSettings.onboardingCompleted], !settings[ShellSettings.askedSensingPermissions] else { return }
        // Screenshot and UI test launches never stop for a permission prompt.
        guard !launchOptions.pinsNavigation, !launchOptions.demoContent else { return }
        requestSensingPermissions()
    }

    // MARK: Routing

    private func route(_ event: HomePadEvent) {
        kiosk.handle(event)
        switch event {
        case .openApp(let id):
            navigator.open(appID: id)
        case .showFace(let id):
            navigator.showFace(id)
        case .goAmbient:
            navigator.goAmbient()
        case .custom(let name, let payload) where name == "openURL":
            if let text = payload.stringValue, let url = URL(string: text) { open(url) }
        case .custom(let name, _) where name == KioskRequest.sleep:
            kiosk.sleepNow()
        case .custom(let name, let payload) where name == KioskRequest.setBrightness:
            if let level = payload.doubleValue { kiosk.setManualBrightness(min(max(level, 0), 1)) }
        case .custom(let name, _) where name == KioskRequest.showDefaultFace:
            navigator.showDefaultFace()
        case .gesture(let gesture):
            handleGesture(gesture)
        default:
            break
        }
    }

    /// A raised palm stops one thing, decided here so one palm never does two:
    /// a ringing timer (Kitchen stops it), else, when `palmControlsMusic` is
    /// on, it toggles the music like a tap on top of a HomePod, so a second
    /// palm resumes. It never touches the assistant: a hand resting near the
    /// face fired a palm every few seconds and closed answers half said.
    private func handleGesture(_ gesture: HandGesture) {
        let media = services.media
        switch gesture {
        case .openPalm:
            guard !services.timers.timers.contains(where: { $0.status == .finished }) else { return }
            if services.assistant.phase == .idle, services.settings[CoreSettings.palmControlsMusic],
               let isPlaying = media.nowPlaying?.isPlaying {
                Task { if isPlaying { await media.pause() } else { await media.play() } }
            }
        default:
            break
        }
    }

    /// Handles `homepad://app/<id>`, `homepad://face/<id>`, `homepad://home` and
    /// `homepad://settings[/<paneID>]`. Other hosts belong to other modules.
    private func open(_ url: URL) {
        guard url.scheme == "homepad" else { return }
        let target = url.pathComponents.first { $0 != "/" }
        switch url.host() {
        case "app": if let target { navigator.open(appID: target) } else { return }
        case "face": if let target { navigator.showFace(target) } else { return }
        case "home": navigator.goHome()
        case "settings": navigator.openSettings(pane: target)
        default: return
        }
        kiosk.handle(.wake)
    }

    // MARK: Kiosk status

    /// Tells other modules what fills the screen, which face it shows, the
    /// brightness and the battery (`AppServices.kioskStatus`). Runs on every
    /// kiosk tick and writes only a change, so nothing redraws for it.
    private func publishKioskStatus() {
        let surface: KioskStatus.Surface
        switch navigator.screen {
        case .ambient: surface = .face
        case .home: surface = .homeScreen
        case .app: surface = .app
        }
        let health = kiosk.health
        let power: KioskStatus.Power? = switch health.power {
        case .charging: .charging
        case .full: .full
        case .unplugged: .unplugged
        case .unknown: nil
        }
        let status = KioskStatus(
            surface: surface,
            faceID: FaceResolver.current(navigator: navigator, household: services.household, settings: services.settings),
            // Whole percent, so a brightness ramp is a few changes rather than one per frame.
            brightness: (kiosk.currentBrightness * 100).rounded() / 100,
            batteryLevel: health.batteryLevel,
            power: power
        )
        if status != services.kioskStatus { services.kioskStatus = status }
    }

    // MARK: Launch arguments

    private func applyLaunchOptions() {
        let options = launchOptions
        // Screenshots and UI tests begin every app from its defaults, and
        // leave what the iPad saved alone.
        if options.pinsNavigation { services.appState.startFresh() }
        let household = services.household
        if let name = options.memberName,
           let member = household.members.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if options.recognized { household.recognize(member.id) } else { household.select(member.id) }
        }
        kiosk.pinnedCondition = options.condition
        kiosk.pinnedProximity = options.proximity
        if options.pinsNavigation { kiosk.returnsToAmbient = false }
        if options.simulateUnplugged {
            kiosk.health.update(power: .unplugged, batteryLevel: 0.42, thermalState: .nominal)
        }
        if let face = options.showFace { navigator.showFace(face) }
        if options.resetHomeScreen { homeLayouts.reset(for: household.activeMemberID) }
        if !options.homeWidgets.isEmpty {
            homeLayouts.update(for: household.activeMemberID) { $0.placeFirst(options.homeWidgets) }
        }
        if let miniWidget = options.headerGlance {
            homeLayouts.update(for: household.activeMemberID) { $0.setMiniWidget(miniWidget) }
        }
        if let page = options.homePage {
            navigator.goHome()
            navigator.pendingHomePage = page
        }
        if options.showHome { navigator.goHome() }
        if let app = options.openApp {
            if let delay = options.openAppDelay {
                navigator.goHome()
                Task { @MainActor [navigator] in
                    try? await Task.sleep(for: .seconds(delay))
                    navigator.open(appID: app)
                }
            } else {
                navigator.open(appID: app)
            }
        }
        if let pane = options.settingsPane { navigator.openSettings(pane: pane) }
        if let gate = options.gateAppID { navigator.presentGate(for: gate) }
        if let sheet = options.homeSheet {
            navigator.goHome()
            navigator.isEditingHomeScreen = true
            navigator.pendingHomeSheet = sheet
        }
        if options.editHomeScreen {
            navigator.goHome()
            navigator.isEditingHomeScreen = true
        }
        if options.editStack {
            navigator.goHome()
            navigator.isEditingHomeScreen = true
            navigator.pendingFirstEdit = .stack
        }
        if let widgetID = options.editWidget {
            navigator.goHome()
            navigator.isEditingHomeScreen = true
            navigator.pendingFirstEdit = .widget(widgetID)
        }
        if let panel = options.panel { navigator.toggle(panel) }
        if options.editControlCenter {
            navigator.panel = .controlCenter
            navigator.isEditingControlCenter = true
        }
        navigator.isShowingOnboarding = options.showOnboarding || options.onboardingStep != nil
            || (!options.pinsNavigation && !services.settings[ShellSettings.onboardingCompleted])
    }
}
