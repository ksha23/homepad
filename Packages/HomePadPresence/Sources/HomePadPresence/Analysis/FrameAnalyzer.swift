@preconcurrency import AVFoundation
import Foundation
import HomePadCore
@preconcurrency import Vision

/// What the main actor wants from the analyzer right now.
struct AnalyzerOptions: Equatable, Sendable {
    var sensitivity: SensingSensitivity = .medium
    /// Run hand pose detection (only when someone is within reach).
    var detectHands = false
    /// Compute face embeddings for recognition.
    var wantsEmbeddings = false
    /// Seconds between recognition samples, from `RecognitionCadence`.
    var embeddingInterval: TimeInterval = 0.5
    /// Samples from the TrueDepth camera need depth for the liveness check, so a
    /// due sample waits briefly for a frame that has some (`RecognitionSampleGate`).
    var embeddingsNeedDepth = false
    /// Describe hands, and liveness checks that failed, for the presence
    /// trace (`-HomePadPresenceTrace`).
    var isTracing = false
    /// Seconds between depth signatures of the face in view
    /// (`DepthFaceSampler`): 0 for one with every face found, nil for none.
    var depthSignatureInterval: TimeInterval?
    /// Draw what the camera and depth sensor see for the recognition debug view.
    var wantsDebugView = false
}

/// Everything learned from one frame, delivered to the main actor.
struct FrameAnalysis: Sendable {
    var observation: SensorObservation
    var embedding: FaceEmbeddingSample?
    var handGesture: HandGesture?
    /// What the hand detector saw, for the presence trace. Nil when not looking
    /// for hands or not tracing.
    var handSummary: String?
    var framesPerSecond: Double
    var backend: BackendKind
    /// The unbroken single-face track of the frame, nil without exactly one
    /// tracked face. Learning from use stops when it changes.
    var faceTrackID: UUID?
    /// Depth tracking events since the last analyzed frame, for the presence trace.
    var traceNotes: [TraceNote] = []
    /// A depth signature of the face on the followed head, when one was due.
    /// Face data: it goes to the depth identity evaluation and nowhere else.
    var depthSignature: DepthSignatureSample?
    /// For the recognition debug view, about four times a second while it is on.
    var debug: RecognitionDebugFrame?
    /// True while a face was found in the depth map on the followed person in
    /// the last `depthFaceHold` seconds. In the dark it is the only face there is.
    var depthFaceSeen = false
    /// The person depth follows, also between maps. In the dark maps came up
    /// to 1.3 s apart, and a frame without the person seen in the last second
    /// ended the look and its votes.
    var followedPersonID: UUID?
}

/// The per-frame pipeline shared by every camera backend: motion, faces,
/// people, depth, hands, recognition embeddings and ambient light.
///
/// Confined to the analysis queue. Only `options` may be set from elsewhere.
final class FrameAnalyzer: @unchecked Sendable {
    private let optionsLock = NSLock()
    private var _options = AnalyzerOptions()
    /// The analysis queue, where the depth face queue's results come back.
    private let queue: DispatchQueue

    /// - Parameter queue: The analysis queue it is confined to.
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// On the CPU from launch until `moveVisionToNeuralEngine()`.
    private let detectors: VisionDetectors = {
        let detectors = VisionDetectors()
        detectors.runOnCPU(true)
        return detectors
    }()
    private let embedder = FaceEmbedder()
    private var motion = MotionDetector()
    /// Depth maps, movement in them and the person followed through them.
    private var depth = DepthSensing()
    /// The face track on that person, from ARKit's faces and Vision's.
    private var follower = FaceFollower()
    private var hands = HandGestureRecognizer()
    private var handTrace = HandTraceThrottle()
    private var frameTimes: [TimeInterval] = []
    private var sampleGate = RecognitionSampleGate()
    private var lastHumanCheck: TimeInterval = -.infinity
    private var lastHumanCount = 0
    private var lastHumanConfidence: Double?
    private var lastHumanBox: CGRect?
    private var lastNearestMeters: Double?
    /// Time of the first frame analyzed since the backend started, for
    /// `AmbientLightMath.roomLux`.
    private var firstFrameTime: TimeInterval?
    /// The depth face of the followed person, and its signatures, on a queue
    /// of its own (`DepthFaceSampler`). One map at a time: while it is busy,
    /// newer maps wait for the next frame.
    private let depthFaces = DepthFaceSampler()
    private let depthFaceQueue = DispatchQueue(label: "com.homepad.presence.depthface", qos: .utility)
    private var depthFaceBusy = false
    /// Results of a sampler that was reset since are dropped.
    private var depthFaceGeneration = 0
    /// A depth signature that came back, for the next analysis.
    private var pendingDepthSignature: DepthSignatureSample?
    /// How far away a depth face found since the last analysis is: the next
    /// analysis counts it as a sighting.
    private var pendingDepthFaceMeters: Double?
    /// The last search and lit depth, for the debug view, and when and on whom
    /// a depth face was last found.
    private var lastDepthSearch: DepthFaceFinder.Search?
    private var lastShadedDepth: (image: CGImage, box: CGRect?)?
    private var depthFaceFound: (time: TimeInterval, person: UUID?)?
    /// A face found on the person stays in view this long, so a few searches
    /// that miss do not end the look and its votes.
    private let depthFaceHold: TimeInterval = 10
    /// Quarter turns that make each backend's frames stand upright, from faces.
    private var upright = UprightCalibration()
    /// The frame being analyzed's backend and orientation before correction.
    private var uprightBase: (backend: BackendKind, orientation: CGImagePropertyOrientation)?
    private let debugRenderer = RecognitionDebugRenderer()
    private var lastDebugFrame: TimeInterval = -.infinity
    private let debugInterval: TimeInterval = 0.25

    /// Seconds between people counts when ARKit already tracks faces.
    private let humanCheckInterval: TimeInterval = 1
    /// Faces farther than this are too small for recognition.
    private let recognitionRangeMeters = 1.6
    /// Hands farther than this are too small for reliable poses.
    private let handRangeMeters = 2.5

    var options: AnalyzerOptions {
        get { optionsLock.withLock { _options } }
        set { optionsLock.withLock { _options = newValue } }
    }

    /// Clears temporal state. Call on the analysis queue when a backend starts.
    func reset() {
        motion.reset()
        depth.reset()
        follower.reset()
        hands = HandGestureRecognizer()
        frameTimes.removeAll()
        lastHumanCount = 0
        lastHumanConfidence = nil
        lastHumanBox = nil
        lastNearestMeters = nil
        firstFrameTime = nil
        resetDepthFaces()
    }

    private func resetDepthFaces() {
        depthFaceGeneration += 1
        depthFaceBusy = false
        pendingDepthSignature = nil
        pendingDepthFaceMeters = nil
        lastDepthSearch = nil
        lastShadedDepth = nil
        depthFaceFound = nil
        let sampler = depthFaces
        depthFaceQueue.async { sampler.reset() }
    }

    /// Loads models before anyone arrives, with requests of its own, so it
    /// runs on a queue of its own while the analysis queue goes on with frames
    /// on the CPU. Vision keeps a loaded model for the whole process, so the
    /// analyzer's requests find it.
    ///
    /// The feature print goes first: recognition needs only it beyond the
    /// detectors the analyzer already runs on the CPU, and it loads in under
    /// 2 s even after a cold boot. `recognitionReady` is called once it has.
    /// Then hand pose, then face and people detection for the Neural Engine,
    /// the slow one after a cold boot.
    static func warmUpModels(
        featurePrint: Bool, detectors: Bool, hands: Bool, recognitionReady: (TimeInterval) -> Void
    ) -> RecognitionWarmUp {
        var report = RecognitionWarmUp()
        guard let buffer = FaceEmbedder.blankFrame(width: 640, height: 480) else { return report }
        if featurePrint {
            report.featurePrint = timed { FaceEmbedder().warmUp() }
            recognitionReady(report.featurePrint ?? 0)
        }
        let warm = VisionDetectors()
        if hands { report.hands = timed { warm.warmUp(on: buffer, faces: false, hands: true) } }
        if detectors { report.faces = timed { warm.warmUp(on: buffer, faces: true, hands: false) } }
        return report
    }

    /// Moves face, people and hand detection from the CPU to where Vision
    /// chooses, once the warm-up has loaded their models there. Call on the
    /// analysis queue.
    func moveVisionToNeuralEngine() {
        detectors.runOnCPU(false)
    }

    private static func timed(_ work: () -> Void) -> TimeInterval {
        let start = Date()
        work()
        return Date().timeIntervalSince(start)
    }

    /// Stores depth that arrived on its own output (AVCapture depth stream),
    /// which matches its video. `horizontalFOVDegrees` is the video's.
    func ingestDepth(_ data: AVDepthData, at time: TimeInterval, horizontalFOVDegrees: Double?) {
        depth.ingest(data, at: time, image: nil, horizontalFOVDegrees: horizontalFOVDegrees)
    }

    /// Call on the analysis queue when face tracking starts: a new session
    /// starts new face tracks, and the trace gets the depth alignment again.
    /// The depth person carries over from the depth scan, but not the depth
    /// faces found there, so no signature mixes the scan's smoothed depth in.
    func startFaceTracking() {
        follower.reset()
        depth.noteAlignmentAgain()
        firstFrameTime = nil
        resetDepthFaces()
    }

    /// Follows the person through TrueDepth depth, and the face track on them,
    /// on every ARKit frame, also the ones not analyzed, so a face that ARKit
    /// loses and finds again between two analyzed frames is still checked
    /// against the depth. Returns the face track (`FaceFollower`).
    func followFaces(_ faces: [ARKitFace], depth data: AVDepthData?, image: ImageGeometry, at time: TimeInterval) -> UUID? {
        if let data {
            depth.ingest(data, at: time, image: image, horizontalFOVDegrees: nil)
        }
        return follower.arkitFrame(faces, hasNewDepth: data != nil, depth: &depth, at: time)
    }

    /// Feeds a face's roll to `upright`. When the correction changes, what was
    /// gathered in the old orientation is dropped.
    private func noteUpright(rollDegrees: Double, source: UprightCalibration.Source) {
        guard let base = uprightBase,
              let line = upright.note(rollDegrees: rollDegrees, backend: base.backend, base: base.orientation, source: source)
        else { return }
        depth.note(TraceNote(key: "upright", text: line, repeats: true))
        if source == .depth { resetDepthFaces() }
    }

    /// Adds a line for the presence trace, delivered with the next analysis.
    func note(_ note: TraceNote) {
        depth.note(note)
    }

    func analyze(_ frame: SensorFrame, backend: BackendKind) -> FrameAnalysis {
        let options = self.options
        let base = frame.orientation
        var frame = frame
        frame.orientation = upright.corrected(base, backend: backend, source: .image)
        frame.depthOrientation = upright.corrected(base, backend: backend, source: .depth)
        uprightBase = (backend, base)
        let time = frame.timestamp
        motion.pixelDelta = options.sensitivity.motionPixelDelta
        motion.areaFraction = options.sensitivity.motionAreaFraction

        var observation = SensorObservation(timestamp: Date(), source: frame.source)
        if let grid = LumaGrid.make(from: frame.pixelBuffer) {
            observation.motion = motion.process(grid)
        }
        observation.depthAgeSeconds = depth.lastArrival.map { time - $0 }
        var depthMoved = false
        // Motion only compares maps with each other, so any new map will do.
        // Face tracking watches for it too: in a dark room ARKit finds no
        // face, and a new session started with no one followed, so movement
        // is the only thing that can pick the person up again.
        if frame.source == .trueDepth, let result = depth.detectMotion(at: time) {
            observation.depthBlobFraction = result.blobFraction
            depthMoved = result.moved
            if result.moved {
                observation.motion = true
                observation.bodyCount = 1
                observation.nearestBodyMeters = result.nearestMeters
            }
        }
        // Liveness can only use depth from the TrueDepth camera itself, of this moment.
        let sampleDepth = frame.source == .trueDepth ? depth.fullMap(at: time, maxAge: 0.25) : nil
        let wantsEmbedding = sampleGate.shouldSample(
            at: time, wanted: options.wantsEmbeddings && (lastNearestMeters ?? .infinity) <= recognitionRangeMeters,
            interval: options.embeddingInterval, hasDepth: sampleDepth != nil,
            needsDepth: options.embeddingsNeedDepth && frame.source == .trueDepth
        )
        let humansDue = frame.trackedFaces == nil || time - lastHumanCheck >= humanCheckInterval
        let handsWanted = options.detectHands && (lastNearestMeters ?? .infinity) <= handRangeMeters
        // While ARKit tracks no face, Vision looks for one at least once a second,
        // with the people count: a head turned past ARKit's reach is still a face
        // to Vision, and it keeps the person and their look.
        let arkitSeesNoFace = frame.trackedFaces?.isEmpty == true
        let facesWanted = frame.trackedFaces == nil || wantsEmbedding || (arkitSeesNoFace && humansDue)
        let vision = detectors.detect(in: frame, faces: facesWanted, humans: humansDue, hands: handsWanted)
        if let roll = vision.faces.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.roll {
            noteUpright(rollDegrees: roll.doubleValue * 180 / .pi, source: .image)
        }

        var faceTrackID = frame.faceTrackID
        if arkitSeesNoFace && facesWanted {
            let seen = visionFaces(vision.faces, frame: frame, sensitivity: options.sensitivity)
            observation.faces = seen
            observation.facesAreTracked = false
            faceTrackID = follower.visionFaces(seen.map { visionFace($0, in: frame) }, depth: &depth, at: time)
        } else {
            observation.faces = frame.trackedFaces ?? visionFaces(vision.faces, frame: frame, sensitivity: options.sensitivity)
            observation.facesAreTracked = frame.trackedFaces != nil
        }
        let depthSignature = sampleDepthFace(in: frame, backend: backend, options: options)
        // A face found in the depth map is a sighting like a camera face. In
        // the dark it is the only one there is: before, someone sitting still
        // was not noticed until they moved.
        let depthFaceMeters = pendingDepthFaceMeters
        pendingDepthFaceMeters = nil
        if let depthFaceMeters {
            observation.bodyCount = max(observation.bodyCount, 1)
            observation.nearestBodyMeters = observation.nearestBodyMeters ?? depthFaceMeters
        }
        if let person = depth.person(at: time) {
            observation.depthPersonMeters = person.distanceMeters
            observation.depthPersonID = person.id
        }
        if humansDue {
            lastHumanCheck = time
            lastHumanCount = vision.humanCount
            lastHumanConfidence = vision.humanConfidence
            lastHumanBox = vision.nearestHuman
        }
        observation.bodyCount = max(observation.bodyCount, lastHumanCount)
        observation.humanConfidence = lastHumanConfidence
        if lastHumanCount > 0, let box = lastHumanBox, let focal = frame.focalLengthPixels {
            observation.bodyEstimateMeters = ProximityMath.distanceMeters(
                faceWidthPixels: Double(box.width) * Double(frame.uprightSize.width), focalLengthPixels: focal,
                faceWidthMeters: ProximityMath.averageUpperBodyWidthMeters
            )
        }
        // Between human checks the count is carried over: it holds presence, but
        // only a frame that found someone itself can help start it.
        observation.isFreshSighting = !observation.faces.isEmpty || depthMoved || depthFaceMeters != nil
            || (humansDue && vision.humanCount > 0)
        let sessionStart = firstFrameTime ?? time
        firstFrameTime = sessionStart
        observation.ambientLux = AmbientLightMath.roomLux(
            brightnessValue: frame.brightnessValue, arkitAmbientIntensity: frame.arkitAmbientIntensity,
            secondsSinceFirstFrame: time - sessionStart
        )
        lastNearestMeters = observation.nearestPersonMeters

        var embedding: FaceEmbeddingSample?
        if wantsEmbedding, let face = vision.faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            let waited = sampleGate.recordSample(at: time)
            embedding = embedder.embed(face, in: frame, depth: sampleDepth)
            // A turned face that reads flat is expected and skipped, so only other failures get the check.
            let failed = embedding?.liveness.map { !$0.isLive && $0.unsure?.isTurned != true } ?? false
            if options.isTracing, failed, let sampleDepth {
                let faceMeters = frame.trackedFaces?.compactMap(\.distanceMeters).min()
                embedding?.livenessCheck = LivenessAlignmentCheck.describe(
                    faceBox: face.boundingBox, in: frame, depth: sampleDepth, faceMeters: faceMeters
                )
            }
            embedding?.depthWaitSeconds = waited
            embedding?.trackID = faceTrackID
            embedding?.visibleFaces = vision.faces.count
        }
        let gesture = hands.process(handsWanted ? vision.hand : nil, at: time)
        let tracesHand = handsWanted && options.isTracing && handTrace.isDue(hasHand: vision.hand != nil, at: time)
        let handSummary = tracesHand ? hands.describe(vision.hand) : nil

        var debug: RecognitionDebugFrame?
        if options.wantsDebugView, time - lastDebugFrame >= debugInterval {
            lastDebugFrame = time
            let full = depth.full.flatMap { time - $0.time < 0.5 ? $0.map : nil }
            debug = debugRenderer.render(
                frame: frame, faces: observation.faces, map: full ?? depth.coarse?.map, person: depth.people.person,
                search: full == nil ? nil : lastDepthSearch, shaded: lastShadedDepth,
                source: depth.lastSource, at: time
            )
        }

        return FrameAnalysis(
            observation: observation, embedding: embedding, handGesture: gesture, handSummary: handSummary,
            framesPerSecond: measureRate(at: time), backend: backend, faceTrackID: faceTrackID,
            traceNotes: depth.takeNotes(), depthSignature: depthSignature, debug: debug,
            depthFaceSeen: depthFaceFound.map {
                time - $0.time <= depthFaceHold && $0.person != nil && $0.person == depth.people.person?.id
            } ?? false,
            followedPersonID: depth.people.person?.id
        )
    }

    /// Hands the newest depth map to the depth face queue when it is free,
    /// and returns a depth signature that came back since the last frame.
    ///
    /// Faces are looked for whether or not anyone is followed yet: a face
    /// found with no one followed starts the person (`DepthSensing.noteFace`).
    /// Signatures come from face tracking's depth only, on a followed person,
    /// since that is the depth the templates were learned from. The depth
    /// scan's is smoothed by iOS.
    private func sampleDepthFace(in frame: SensorFrame, backend: BackendKind, options: AnalyzerOptions) -> DepthSignatureSample? {
        defer { pendingDepthSignature = nil }
        guard frame.source == .trueDepth, !depthFaceBusy, let full = depth.full else { return pendingDepthSignature }
        let person = depth.people.person?.id
        let job = DepthFaceSampler.Job(
            map: full.map, mapTime: full.time, person: person, orientation: frame.depthOrientation ?? frame.orientation,
            signatureInterval: backend == .faceTracking && person != nil ? options.depthSignatureInterval : nil,
            time: frame.timestamp, isTracing: options.isTracing
        )
        let expression = frame.faceExpression
        let generation = depthFaceGeneration
        let sampler = depthFaces
        depthFaceBusy = true
        depthFaceQueue.async { [weak self, queue] in
            let result = sampler.process(job)
            queue.async { self?.apply(result, of: job, expression: expression, generation: generation) }
        }
        return pendingDepthSignature
    }

    /// A depth face result, back on the analysis queue: it starts or confirms
    /// the person, teaches which way the depth stands, and holds a sighting
    /// and a signature for the next analysis.
    private func apply(_ result: DepthFaceSampler.Result, of job: DepthFaceSampler.Job, expression: Double?, generation: Int) {
        guard generation == depthFaceGeneration else { return }
        depthFaceBusy = false
        if let search = result.search { lastDepthSearch = search }
        if let shaded = result.shaded { lastShadedDepth = shaded }
        result.notes.forEach { depth.note($0) }
        if let face = result.face {
            if depth.people.person?.id == job.person {
                depth.noteFace(at: face.nosePoint, meters: face.noseMeters, time: job.time)
            }
            // A face that started the person is theirs.
            depthFaceFound = (job.time, job.person ?? depth.people.person?.id)
            pendingDepthFaceMeters = face.noseMeters
        }
        if let points = result.signature {
            pendingDepthSignature = DepthSignatureSample(signature: DepthSignature(points: points), expression: expression)
        }
        if let roll = result.roll { noteUpright(rollDegrees: roll, source: .depth) }
    }

    /// Faces from Vision, with distance from face size and gaze from head pose.
    private func visionFaces(_ faces: [VNFaceObservation], frame: SensorFrame, sensitivity: SensingSensitivity) -> [DetectedFace] {
        let focal = frame.focalLengthPixels
        let width = Double(frame.uprightSize.width)
        return faces.compactMap { face in
            guard Double(face.boundingBox.width) >= sensitivity.minimumFaceWidth else { return nil }
            let distance = focal.flatMap {
                ProximityMath.distanceMeters(faceWidthPixels: Double(face.boundingBox.width) * width, focalLengthPixels: $0)
            }
            let looking = GazeMath.isFacingScreen(yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue)
            return DetectedFace(distanceMeters: distance, isLookingAtScreen: looking, boundingBox: face.boundingBox)
        }
    }

    /// A Vision face as the face follower takes it: its center in the native
    /// image and its distance by its size.
    private func visionFace(_ face: DetectedFace, in frame: SensorFrame) -> VisionFace {
        let native = frame.nativeRect(fromUpright: face.boundingBox ?? .zero)
        return VisionFace(point: CGPoint(x: native.midX, y: 1 - native.midY), expectedMeters: face.distanceMeters)
    }

    private func measureRate(at time: TimeInterval) -> Double {
        frameTimes.append(time)
        frameTimes.removeAll { time - $0 > 2 }
        guard let first = frameTimes.first, frameTimes.count > 1, time > first else { return 0 }
        return Double(frameTimes.count - 1) / (time - first)
    }
}

/// How long each model took to load at launch, for the presence trace. Nil
/// for a model this warm-up did not load.
struct RecognitionWarmUp: Sendable {
    var featurePrint: TimeInterval?
    var hands: TimeInterval?
    /// Face and people detection, for the Neural Engine.
    var faces: TimeInterval?

    var total: TimeInterval { (featurePrint ?? 0) + (hands ?? 0) + (faces ?? 0) }

    var description: String {
        let ms = { (seconds: TimeInterval) in "\(Int((seconds * 1000).rounded())) ms" }
        let parts = [featurePrint.map { "feature print \(ms($0))" }, hands.map { "hands \(ms($0))" },
                     faces.map { "faces \(ms($0))" }].compactMap { $0 }
        return "\(ms(total)) (" + parts.joined(separator: ", ") + ")"
    }
}
