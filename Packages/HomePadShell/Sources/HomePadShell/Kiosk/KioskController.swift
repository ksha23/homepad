import CoreGraphics
import Foundation
import HomePadCore
import Observation

/// The always-on brain. Keeps Auto-Lock off, decides the display condition
/// (active, ambient, dimmed, night, sleeping) from touches, presence, room light,
/// time of day and settings, has `KioskBrightness` ramp the screen to match,
/// shifts ambient content against burn-in, and reacts to power and heat.
///
/// It writes the result to `services.displayCondition` for other modules, and
/// the shell passes `condition` and `proximity` into the SwiftUI environment.
@MainActor
@Observable
final class KioskController {
    private(set) var state = KioskState.initial
    /// Nearest person's distance bucket for apps, the Home Screen and overlays.
    /// `.near` while someone uses the screen, until a minute after their last touch.
    private(set) var proximity: ProximityLevel = .far
    /// The same for the face, which follows the camera even right after a touch,
    /// so it goes back to its across-the-room layout as soon as someone walks away.
    /// A face has two looks, so it is `.near` or `.far`: up close only within
    /// reach (`.near`, about a meter), and across the room at any distance past it.
    private(set) var faceProximity: ProximityLevel = .far
    /// Offset to apply to ambient content (burn-in protection).
    private(set) var burnInOffset: CGSize = .zero
    private(set) var isRunning = false
    let health: DeviceHealthMonitor

    /// Pins the condition instead of computing it (screenshot launch arguments).
    var pinnedCondition: DisplayCondition?
    /// Pins proximity instead of reading presence (`-HomePadProximity`).
    var pinnedProximity: ProximityLevel?
    /// When false, interaction never times out and the person signed in stays,
    /// so a debug launch screen stays put.
    var returnsToAmbient = true
    /// Called once each time interaction times out, so navigation returns to the face.
    @ObservationIgnored var onInteractionEnded: (() -> Void)?
    /// Called at the end of every tick, so the shell can report what it shows.
    @ObservationIgnored var onTick: (() -> Void)?

    var condition: DisplayCondition { state.condition }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let dependencies: KioskDependencies
    @ObservationIgnored private let brightness: KioskBrightness
    @ObservationIgnored private var lastInteraction: Date
    @ObservationIgnored private var lastEngagement: Date
    /// Last finger on the screen. Wake events and holds are not touches.
    @ObservationIgnored private(set) var lastTouch = Date.distantPast
    @ObservationIgnored private var pausedPresenceForHeat = false
    /// When a request put the screen to sleep (`sleepNow()`). It sleeps until a
    /// touch or wake event after that, or until someone arrives.
    @ObservationIgnored private var sleepRequestedAt: Date?
    /// Whether presence saw someone at the last tick, to notice an arrival.
    @ObservationIgnored private var wasSomeonePresent = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let log = Log.make("Kiosk")

    init(services: AppServices, dependencies: KioskDependencies) {
        self.services = services
        self.dependencies = dependencies
        self.health = dependencies.health
        self.brightness = KioskBrightness(dependencies: dependencies)
        let now = dependencies.clock()
        lastInteraction = now
        lastEngagement = now
    }

    // MARK: Lifecycle

    /// Takes over the display: saves the user's brightness, disables Auto-Lock and starts ticking.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        brightness.takeOver()
        registerInteraction()
        tick()
        let interval = dependencies.tickInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.tick()
            }
        }
        log.info("Kiosk started")
    }

    /// Gives the display back: restores the user's brightness and re-enables Auto-Lock.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        loop?.cancel()
        loop = nil
        brightness.handBack()
        dependencies.setIdleTimerDisabled(false)
        log.info("Kiosk stopped")
    }

    // MARK: Inputs

    /// Any touch anywhere on screen. The household's session decides whether it
    /// keeps the person signed in: only while the camera sees no face or sees
    /// that person (`MemberSession`).
    func noteTouch() {
        let wasAwake = state.isInteracting && state.condition != .sleeping
        lastTouch = dependencies.clock()
        registerInteraction()
        services.household.noteActivity(now: dependencies.clock())
        if !wasAwake { tick() }
    }

    /// Reacts to bus events: alerts wake the screen, `.goAmbient` ends interaction.
    func handle(_ event: HomePadEvent) {
        switch event {
        case .wake, .doorbellRang, .timerFinished, .soundDetected, .intercomReceived, .invokeAssistant, .openApp:
            registerInteraction()
        case .memberRecognized, .gesture, .headGesture:
            lastEngagement = dependencies.clock()
        case .showFace:
            // A face asked for shows, even on a screen asked to sleep.
            lastEngagement = dependencies.clock()
            sleepRequestedAt = nil
        case .custom(let name, _) where name == KioskRequest.showDefaultFace:
            lastEngagement = dependencies.clock()
            sleepRequestedAt = nil
        case .goAmbient:
            lastInteraction = .distantPast
        case .presenceChanged:
            break
        default:
            return
        }
        tick()
    }

    /// Brightness picked by hand in Control Center. Holds until the condition changes.
    func setManualBrightness(_ value: Double) {
        brightness.setManual(value, condition: state.condition)
    }

    /// Sleeps the screen now, as a request from Home Assistant asks. Unlike the
    /// sleep timer, someone already in front of the iPad does not keep it awake.
    /// It wakes on a touch, a wake event, a screen holding itself awake, or
    /// someone arriving.
    func sleepNow() {
        sleepRequestedAt = dependencies.clock()
        lastInteraction = .distantPast
        tick()
    }

    /// Brightness right now, for sliders.
    var currentBrightness: Double { brightness.current }

    // MARK: Evaluation

    /// Re-evaluates everything. Runs every `tickInterval` and after inputs change.
    func tick() {
        let now = dependencies.clock()
        let snapshot = dependencies.presence?() ?? services.presence.snapshot
        if snapshot.isSomeonePresent && (snapshot.proximity >= .mid || snapshot.isLookingAtScreen) {
            lastEngagement = now
        }
        if holdsInteraction { lastInteraction = now }
        let arrived = snapshot.isSomeonePresent && !wasSomeonePresent
        wasSomeonePresent = snapshot.isSomeonePresent

        let previous = state
        let tuning = KioskTuning(settings: services.settings)
        var next = DisplayConditionPolicy.evaluate(KioskInputs(
            now: now, lastInteraction: lastInteraction, lastEngagement: lastEngagement,
            presence: snapshot, tuning: tuning
        ))
        if let requested = sleepRequestedAt {
            if lastInteraction >= requested || arrived {
                sleepRequestedAt = nil
            } else {
                next.condition = .sleeping
                next.isInteracting = false
            }
        }
        if let pinnedCondition { next.condition = pinnedCondition }
        if next != state { state = next }
        if services.displayCondition != next.condition { services.displayCondition = next.condition }

        updateProximity(snapshot, now: now, tuning: tuning)
        updateBurnIn(now)
        brightness.update(for: state, presence: snapshot, settings: services.settings, cap: health.brightnessCap)
        reactToHeat()
        dependencies.setIdleTimerDisabled(services.settings[ShellSettings.keepScreenOn])
        // The session's only clock: it ends a set time after its person was last detected.
        if returnsToAmbient { services.household.expireIfNeeded(now: now) }
        if Self.trace.isEnabled { traceSession() }

        if previous.isInteracting && !next.isInteracting {
            onInteractionEnded?()
        }
        onTick?()
    }

    // MARK: Private

    private func registerInteraction() {
        let now = dependencies.clock()
        lastInteraction = now
        lastEngagement = now
    }

    /// Things that keep the screen "in use" without touches: a debug pin, a
    /// conversation with the assistant, a feature holding a camera (Mirror), or
    /// a screen that asked to stay active (cooking mode, via `keepsDisplayActive`).
    private var holdsInteraction: Bool {
        if !returnsToAmbient { return true }
        if !services.displayHolds.isEmpty { return true }
        switch services.assistant.phase {
        case .listening, .thinking, .speaking: return true
        case .idle, .error: break
        }
        return services.capture.foregroundClaim != nil
    }

    private func updateProximity(_ snapshot: PresenceSnapshot, now: Date, tuning: KioskTuning) {
        let measured: ProximityLevel = snapshot.isSomeonePresent ? max(snapshot.proximity, .far) : .far
        // A recent interaction means someone is close, unless the camera is watching
        // and sees nobody: then they walked away, and the face goes back to its
        // across-the-room layout at once instead of a minute later.
        let cameraWatches = services.presence.isCameraSensing
        let stillHere = state.isInteracting && (snapshot.isSomeonePresent || !cameraWatches)
        // Apps and the Home Screen stay near for as long as a touch keeps them open,
        // whatever the camera sees. The camera also loses someone standing right at
        // the iPad, above all in a dark room, where it cannot make out their body.
        // The Home app's tiles grew each time the lights went off and shrank again
        // when they came back on.
        let touchedRecently = state.isInteracting && now.timeIntervalSince(lastTouch) < tuning.returnToFaceAfter
        // The face's up close look starts within reach. Counting the middle of the room as up close
        // (`.mid`, up to 2.5 m) left the across-the-room look for an empty room only. While the camera
        // watches, the face goes by the distance it measures and nothing else: seeing someone keeps the
        // screen in use, which held the up close look for a person across the room until they left the
        // camera's view. Without the camera, a screen in use means someone is at it.
        let faceMeasured: ProximityLevel = measured == .near ? .near : .far
        let faceUnwatched: ProximityLevel = state.isInteracting ? .near : .far
        let face = pinnedProximity ?? (cameraWatches ? faceMeasured : faceUnwatched)
        let value = pinnedProximity ?? (stillHere || touchedRecently ? .near : measured)
        if Self.trace.isEnabled {
            traceProximity(value, face: face, touchedRecently: touchedRecently, snapshot: snapshot, cameraWatches: cameraWatches)
        }
        if value != proximity { proximity = value }
        if face != faceProximity { faceProximity = face }
    }

    private func traceProximity(
        _ value: ProximityLevel, face: ProximityLevel, touchedRecently: Bool, snapshot: PresenceSnapshot, cameraWatches: Bool
    ) {
        let distance = snapshot.nearestDistanceMeters.map { String(format: "%.1fm", $0) } ?? "-"
        let camera: String = services.capture.foregroundClaim.map { String(describing: $0) } ?? "-"
        let sensed = "present \(snapshot.isSomeonePresent) \(snapshot.proximity) \(distance) watching \(cameraWatches)"
        let interaction = "interacting \(state.isInteracting) touched \(touchedRecently) holds \(holdsInteraction) "
            + "displayHolds \(services.displayHolds.count)"
        let other = "camera claim \(camera) assistant \(services.assistant.phase)"
        Self.trace.logIfChanged("proximity", "proximity \(value) face \(face) from \(sensed), \(interaction), \(other)")
    }

    /// Who is signed in and why, each time it changes.
    private func traceSession() {
        let session = services.household.session
        let name = session.mode.memberID.flatMap { id in services.household.members.first { $0.id == id }?.name } ?? "nobody"
        Self.trace.logIfChanged("session", "session \(session.mode) (\(name)), owner in view \(session.isOwnerInView), "
            + "camera \(session.view), timeout \(Int(session.timeout)) s")
    }

    /// With `-HomePadPresenceTrace YES`, why the face thinks someone is near.
    private static let trace = DebugTrace(file: "kiosk-trace.txt", argument: "HomePadPresenceTrace")

    private func updateBurnIn(_ now: Date) {
        let enabled = services.settings[ShellSettings.burnInProtection] && !state.isInteracting
        let amplitude = enabled ? services.settings[ShellSettings.burnInAmplitude] : 0
        let offset = BurnInShift.offset(at: now, amplitude: amplitude)
        if offset != burnInOffset { burnInOffset = offset }
    }

    /// Critical heat pauses presence sensing (the camera is the biggest heat source
    /// HomePad controls). It resumes once the iPad cools down.
    private func reactToHeat() {
        if health.thermalState == .critical, !pausedPresenceForHeat, services.presence.isRunning {
            services.presence.stop()
            pausedPresenceForHeat = true
            log.warning("Critical thermal state, pausing presence sensing")
        } else if pausedPresenceForHeat, !health.isOverheating {
            services.presence.start()
            pausedPresenceForHeat = false
            log.info("Cooled down, resuming presence sensing")
        }
    }
}
