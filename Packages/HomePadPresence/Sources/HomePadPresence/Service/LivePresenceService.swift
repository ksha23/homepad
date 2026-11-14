import Foundation
import HomePadCore
import Observation

/// HomePad's sensing layer: TrueDepth or front-camera presence, distance,
/// gaze, people count, ambient light, recognition, gestures and sounds.
///
/// Installed into `services.presence`. Posts `.presenceChanged` when presence
/// or the proximity bucket changes, `.memberRecognized`, `.gesture`,
/// `.headGesture`, `.motionDetected` and `.soundDetected`.
@MainActor
@Observable
public final class LivePresenceService: PresenceService {
    public private(set) var snapshot = PresenceSnapshot.empty
    public private(set) var isRunning = false
    public var hasTrueDepth: Bool { capabilities.hasTrueDepth }
    /// The current duty-cycle mode.
    private(set) var mode: SensingMode = .off(.stopped)
    public var isCameraSensing: Bool { mode.usesCamera }

    let diagnostics = PresenceDiagnostics()
    let recognition: FaceRecognitionService
    let sounds: SoundAlertService
    let headGestures: HeadGestureService

    @ObservationIgnored let capabilities: SensingCapabilities
    @ObservationIgnored let services: AppServices
    @ObservationIgnored let conditions = SensingConditions()
    @ObservationIgnored private let sensors: SensingCoordinator
    @ObservationIgnored private let microphoneActivity: MicrophoneActivityMonitor
    @ObservationIgnored private let policy = DutyCyclePolicy()
    @ObservationIgnored private var fusion = PresenceFusion()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var didWarmUpRecognition = false
    @ObservationIgnored private var didWarmUpDetectors = false
    /// True while the recognition models load after launch. Samples and hand
    /// pose wait for them, so no frame stalls on the load, and presence and
    /// distance run from the first frame. The people button shows it.
    public private(set) var isRecognitionStarting = false
    /// What the camera and depth sensor see, for the recognition debug view.
    /// Nil while it is off. In memory only.
    private(set) var debugView: RecognitionDebugState?
    @ObservationIgnored private var faceTrackingFailed = false
    @ObservationIgnored private var lastMotionEvent = Date.distantPast
    /// The settings the per-frame path reads.
    private var frameSettings: FrameSettings { FrameSettings(services.settings) }
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// The light the running backend was chosen by (`selectionLight`).
    @ObservationIgnored private var selectedLight: AmbientLight?
    /// How long a light reading counts for choosing a backend.
    private let lightReadingLifetime: TimeInterval = 3 * 60
    @ObservationIgnored var observationTasks: [Task<Void, Never>] = []

    private let log = Log.make("Presence")
    /// Minimum seconds between `.motionDetected` events.
    private let motionEventInterval: TimeInterval = 5

    init(services: AppServices, launchOptions: PresenceLaunchOptions = .current) {
        self.services = services
        let simulated = launchOptions.simulation.map(SimulatedPresenceScript.init(mode:))
        capabilities = SensingCapabilities(
            hasTrueDepth: FaceTrackingBackend.isSupported,
            hasFrontCamera: CameraSession.device(for: .front) != nil,
            isSimulated: simulated != nil
        )
        sensors = SensingCoordinator(script: simulated, capture: services.capture)
        microphoneActivity = MicrophoneActivityMonitor(services: services)
        let directory = try? FaceTemplateStore.defaultDirectory()
        recognition = FaceRecognitionService(services: services, store: directory.map { FaceTemplateStore(directory: $0) })
        sounds = SoundAlertService(services: services)
        headGestures = HeadGestureService(services: services)
        wireComponents()
    }

    // MARK: PresenceService

    /// Starts sensing. Only on a HomePad: a companion iPhone or Mac never runs
    /// the camera or listens for sounds (`AppRole`).
    public func start() {
        guard !isStarted, AppRole.current == .homePad else { return }
        isStarted = true
        isRunning = true
        recognition.load()
        recognition.reconcile(with: services.household.members)
        warmUpRecognition()
        conditions.start()
        startObserving()
        refreshFeatures()
        reevaluate()
    }

    public func stop() {
        isStarted = false
        isRunning = false
        reevaluate()
    }

    /// Asks for camera and microphone access (from onboarding or settings).
    func requestPermissions() async {
        if CameraPermission.status == .undetermined { _ = await CameraPermission.request() }
        if MicrophonePermission.status == .undetermined { _ = await MicrophonePermission.request() }
        refreshFeatures()
        reevaluate()
    }

    /// Loads models before anyone arrives: the feature print once there are
    /// templates to match, so the first sample of the first visit is as fast
    /// as the rest, and face, people and hand detection once a launch, so the
    /// analyzer can move them from the CPU to the Neural Engine. Also called
    /// when the templates become readable after the iPad unlocks.
    func warmUpRecognition() {
        guard !capabilities.isSimulated, capabilities.hasTrueDepth || capabilities.hasFrontCamera else { return }
        let detectors = !didWarmUpDetectors
        let featurePrint = !didWarmUpRecognition && recognition.isEnabled && !recognition.templates.isEmpty
        guard detectors || featurePrint else { return }
        didWarmUpDetectors = true
        if featurePrint {
            didWarmUpRecognition = true
            isRecognitionStarting = true
            updateAnalyzerOptions()
        }
        let start = Date()
        sensors.warmUp(featurePrint: featurePrint, detectors: detectors, hands: detectors && frameSettings.handGestures) { [weak self] _ in
            PresenceTrace.trace.log("recognition ready \(PresenceTrace.format(Date().timeIntervalSince(start))) s after its warm-up began")
            self?.isRecognitionStarting = false
            self?.updateAnalyzerOptions()
        } completion: { report in
            PresenceTrace.trace.log("vision warm-up took \(report.description)"
                + (detectors ? ", detection moved from the CPU to the Neural Engine" : ""))
        }
    }

    // MARK: Duty cycle

    /// Recomputes the duty-cycle mode and applies it to the sensors.
    func reevaluate() {
        let inputs = currentInputs()
        let now = Date()
        let newMode = policy.mode(for: inputs, now: now)
        if newMode != mode { log.info("Sensing mode \(newMode.title, privacy: .public)") }
        mode = newMode
        diagnostics.mode = newMode
        diagnostics.thermalState = conditions.thermalState

        let light = selectionLight(at: now)
        selectedLight = light
        let kind = BackendSelector.kind(
            for: newMode, capabilities: capabilities,
            preferTrueDepth: frameSettings.useTrueDepth && !faceTrackingFailed,
            ambientLight: light
        )
        sensors.apply(kind: kind, mode: newMode)
        if case .microphoneOnly = newMode { microphoneActivity.start() } else { microphoneActivity.stop() }
        if !newMode.usesCamera && !isMicrophoneMode { fusion.reset() }
        updateTicking()
        publish(fusion.snapshot)
        updateAnalyzerOptions()
        scheduleTransition(policy.nextTransition(for: inputs, now: now))
    }

    private var isMicrophoneMode: Bool {
        if case .microphoneOnly = mode { return true }
        return false
    }

    private var isActiveMode: Bool {
        if case .active = mode { return true }
        return false
    }

    private func currentInputs() -> DutyCycleInputs {
        DutyCycleInputs(
            isStarted: isStarted,
            isAppActive: conditions.isAppActive,
            camera: conditions.cameraAvailability(services: services, capabilities: capabilities),
            isMicrophoneAvailable: conditions.isMicrophoneAvailable(services: services),
            thermalState: conditions.thermalState,
            lastPresenceAt: fusion.lastCameraPresenceAt
        )
    }

    private func scheduleTransition(_ date: Date?) {
        transitionTask?.cancel()
        guard let date else { return }
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.reevaluate()
        }
    }

    /// Lets presence lapse when frames stop arriving, once a second while a
    /// camera or the microphone senses. With both off the fusion was just reset
    /// and has nothing to expire, so the loop stops instead of waking all day.
    private func updateTicking() {
        guard mode.usesCamera || isMicrophoneMode else {
            tickTask?.cancel()
            tickTask = nil
            return
        }
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.publish(self.fusion.tick(now: Date()))
                if self.selectionLight(at: Date()) != self.selectedLight { self.reevaluate() }
            }
        }
    }

    // MARK: Readings

    private func wireComponents() {
        sensors.deliver = { [weak self] analysis in self?.handle(analysis) }
        sensors.failed = { [weak self] kind, message in self?.backendFailed(kind, message) }
        sensors.simulatedRecognitionTarget = { [weak self] in
            self?.recognition.templates.values.first.map { SyntheticFace.identity(for: $0.memberID) }
        }
        microphoneActivity.onActivity = { [weak self] observation in
            guard let self else { return }
            self.publish(self.fusion.ingest(observation))
        }
        recognition.onRecognized = { [weak self] memberID in
            self?.fusion.setRecognizedMember(memberID)
        }
    }

    private func handle(_ analysis: FrameAnalysis) {
        guard mode.usesCamera else { return }
        diagnostics.record(analysis)
        if PresenceTrace.trace.isEnabled {
            let observation = analysis.observation
            let nearest = snapshot.nearestDistanceMeters.map { String(format: "%.1fm", $0) } ?? "-"
            let human = observation.humanConfidence.map(PresenceTrace.format) ?? "-"
            let depth = observation.depthBlobFraction.map(PresenceTrace.format) ?? "-"
            let depthAge = observation.depthAgeSeconds.map { String(format: "%.1fs", $0) } ?? "none"
            let body = observation.bodyEstimateMeters.map { String(format: "%.1fm", $0) } ?? "-"
            let person = observation.depthPersonMeters.map { String(format: "%.1fm", $0) } ?? "-"
            // This frame's own reading, in whole lux, before smoothing.
            let lux = observation.ambientLux.map { String(Int($0.rounded())) } ?? "-"
            PresenceTrace.trace.logIfChanged("frame", "frame \(mode.title) backend \(analysis.backend.rawValue) "
                + "present \(snapshot.isSomeonePresent) faces \(observation.faces.count) tracked \(observation.facesAreTracked) "
                + "bodies \(observation.bodyCount) fresh \(observation.isFreshSighting) human \(human) body \(body) depth patch \(depth) age \(depthAge) "
                + "depth person \(person) light \(fusion.snapshot.ambientLight.map { "\($0)" } ?? "-") lux \(lux) "
                + "nearest \(nearest) embeddings \(sensors.analyzer.options.wantsEmbeddings) "
                + "recognized \(snapshot.recognizedMemberID != nil)")
            for note in analysis.traceNotes {
                if note.repeats {
                    PresenceTrace.trace.log(note.text)
                } else {
                    PresenceTrace.trace.logIfChanged(note.key, note.text)
                }
            }
        }
        if let hand = analysis.handSummary { PresenceTrace.trace.logIfChanged("hand", hand) }
        // Every frame, so a break in face tracking stops learning even between
        // samples, and a new face starts a new look before its first sample.
        // In the dark the camera sees no face, but the depth map does: that
        // face, on the followed person, is the face in view.
        let cameraFaces = analysis.observation.faces.count
        let depthOnly = cameraFaces == 0 && analysis.depthFaceSeen
            && recognition.isTooDarkForCamera(light: snapshot.ambientLight, at: Date())
        recognition.noteFaces(
            count: depthOnly ? 1 : cameraFaces,
            track: depthOnly ? analysis.observation.depthPersonID : analysis.faceTrackID
        )
        if !analysis.observation.faces.isEmpty {
            recognition.noteFace(backend: analysis.backend, isPresent: snapshot.isSomeonePresent)
        }
        let wasScanning = !isActiveMode
        _ = fusion.ingest(analysis.observation)
        if analysis.observation.motion { noteMotion(analysis.backend) }
        if let embedding = analysis.embedding {
            recognition.consider(embedding, requireLiveness: requiresLiveness(analysis.backend))
        }
        if let signature = analysis.depthSignature {
            recognition.considerDepthSignature(signature, track: analysis.faceTrackID, light: fusion.snapshot.ambientLight)
        }
        if let gesture = analysis.handGesture, frameSettings.handGestures {
            PresenceTrace.trace.log("hand gesture \(gesture.rawValue)")
            services.events.post(.gesture(gesture))
        }
        publish(fusion.snapshot)
        if let debug = analysis.debug {
            debugView = RecognitionDebugState(frame: debug, lines: debugLines(analysis, frame: debug))
        }
        // A sighting wakes the full-rate path. A light change may switch between
        // the RGB and depth scans, or between face tracking and the depth scan.
        let lightChanged = selectionLight(at: Date()) != selectedLight
        if (wasScanning && analysis.observation.detectsPerson) || lightChanged {
            reevaluate()
        } else {
            updateAnalyzerOptions()
        }
    }

    /// The light the backend choice goes by: the last reading, or nil once it
    /// is older than `lightReadingLifetime`. The depth scan cannot measure the
    /// light, so without this a dark room's depth scan would run on after the
    /// lamps came on. Nil starts a backend that measures it (the front camera,
    /// or face tracking while someone is present), and a dark reading goes
    /// back to the depth scan.
    private func selectionLight(at now: Date) -> AmbientLight? {
        guard let measured = fusion.lastLuxAt, now.timeIntervalSince(measured) < lightReadingLifetime else { return nil }
        return fusion.snapshot.ambientLight
    }

    private func requiresLiveness(_ backend: BackendKind) -> Bool {
        backend != .simulated && capabilities.hasTrueDepth && frameSettings.useTrueDepth
    }

    private func noteMotion(_ backend: BackendKind) {
        let now = Date()
        guard frameSettings.motionEvents, now.timeIntervalSince(lastMotionEvent) >= motionEventInterval else { return }
        lastMotionEvent = now
        services.events.post(.motionDetected(source: backend == .depthScan ? "depth" : "camera"))
    }

    private func backendFailed(_ kind: BackendKind, _ message: String) {
        diagnostics.lastError = message
        log.error("Backend \(kind.rawValue, privacy: .public) failed: \(message, privacy: .public)")
        if kind == .faceTracking {
            // Fall back to the RGB path rather than leaving the room unwatched.
            faceTrackingFailed = true
            reevaluate()
        }
    }

    /// Publishes a new snapshot when something meaningful changed, and posts events.
    /// Every call also tells the household's session what the camera sees.
    func publish(_ new: PresenceSnapshot) {
        defer {
            recognition.updateSensing(isWatching: mode.usesCamera, isSomeonePresent: snapshot.isSomeonePresent)
        }
        let old = snapshot
        let presenceChanged = new.isSomeonePresent != old.isSomeonePresent || new.proximity != old.proximity
        let meaningful = presenceChanged || new.peopleCount != old.peopleCount
            || new.isLookingAtScreen != old.isLookingAtScreen || new.recognizedMemberID != old.recognizedMemberID
            || new.ambientLight != old.ambientLight || new.source != old.source
        let distanceMoved = abs((new.nearestDistanceMeters ?? -1) - (old.nearestDistanceMeters ?? -1)) > 0.1
        let activityMoved = new.lastActivity.timeIntervalSince(old.lastActivity) > 5
        guard meaningful || distanceMoved || activityMoved else { return }
        snapshot = new
        if presenceChanged { services.events.post(.presenceChanged(new)) }
        if old.isSomeonePresent && !new.isSomeonePresent { recognition.presenceEnded() }
    }

    /// Tells the analyzer what to compute, so work scales with what is needed.
    /// Runs on every frame, so its settings come from `frameSettings`.
    func updateAnalyzerOptions() {
        let settings = frameSettings
        let within = (snapshot.nearestDistanceMeters ?? .infinity) <= 2.5
        let wouldSample = recognition.wantsEmbeddings && snapshot.isSomeonePresent
        let wantsEmbeddings = wouldSample && !isRecognitionStarting
        let now = Date()
        let interval = recognition.sampleInterval(at: now)
        let purpose = recognition.isSamplingOnlyToLearn(at: now) ? "learning" : "recognition"
        sensors.analyzer.options = AnalyzerOptions(
            sensitivity: settings.sensitivity,
            detectHands: settings.handGestures && snapshot.isSomeonePresent && within && !isRecognitionStarting,
            wantsEmbeddings: wantsEmbeddings,
            embeddingInterval: interval,
            embeddingsNeedDepth: capabilities.hasTrueDepth && settings.useTrueDepth,
            isTracing: PresenceTrace.trace.isEnabled,
            depthSignatureInterval: recognition.wantsDepthSignatures
                ? recognition.depthSignatureInterval(light: snapshot.ambientLight, at: now) : nil,
            wantsDebugView: settings.recognitionDebug && mode.usesCamera
        )
        if !settings.recognitionDebug || !mode.usesCamera, debugView != nil { debugView = nil }
        let cadence = wantsEmbeddings ? "\(purpose) samples every \(PresenceTrace.format(interval)) s"
            : wouldSample ? "recognition waits for its models" : "recognition sampling off"
        PresenceTrace.trace.logIfChanged("cadence", cadence)
    }

    /// Re-applies feature switches (sounds, head gestures).
    func refreshFeatures() {
        sounds.update()
        headGestures.update()
    }
}
