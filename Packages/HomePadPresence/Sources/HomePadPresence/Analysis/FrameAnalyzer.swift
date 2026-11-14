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
    /// Seconds between depth signatures of the face in view, for the depth
    /// identity evaluation. Nil while none are wanted.
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
    /// True while the depth map shows a face on the followed person (found in
    /// the last second). In the dark it is the only face there is.
    var depthFaceSeen = false
}

/// The per-frame pipeline shared by every camera backend: motion, faces,
/// people, depth, hands, recognition embeddings and ambient light.
///
/// Confined to the analysis queue. Only `options` may be set from elsewhere.
final class FrameAnalyzer: @unchecked Sendable {
    private let optionsLock = NSLock()
    private var _options = AnalyzerOptions()

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
    /// When the depth map was last searched for a face, and a signature last taken.
    private var lastDepthFaceSearch: TimeInterval = -.infinity
    private var lastDepthSignature: TimeInterval = -.infinity
    /// Seconds between searches of the depth map for a face.
    private let depthFaceInterval: TimeInterval = 0.5
    /// The last search's face, kept for the debug view between searches.
    private var lastDepthFace: (face: DepthFace?, searched: Bool) = (nil, false)
    /// When a depth face was last found, and on which person.
    private var depthFaceFound: (time: TimeInterval, person: UUID)?
    /// Capture time of the last depth map searched, so each is searched once.
    private var lastDepthFaceMap: TimeInterval = -.infinity
    /// Depth faces collected for the next signature (`DepthFaceFusion`): every
    /// new depth map is searched until enough are merged or `burstSeconds` passed.
    private var burst: (person: UUID, startedAt: TimeInterval, faces: [DepthFace])?
    private let burstSeconds: TimeInterval = 1.2
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
        lastDepthFaceSearch = -.infinity
        lastDepthSignature = -.infinity
        lastDepthFace = (nil, false)
        depthFaceFound = nil
        lastDepthFaceMap = -.infinity
        burst = nil
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
        depth.ingest(data, at: time, image: nil, horizontalFOVDegrees: horizontalFOVDegrees, keepFull: keepsFullDepth)
    }

    /// Call on the analysis queue when face tracking starts: a new session
    /// starts new face tracks, and the trace gets the depth alignment again.
    func startFaceTracking() {
        follower.reset()
        depth.noteAlignmentAgain()
        firstFrameTime = nil
    }

    /// Follows the person through TrueDepth depth, and the face track on them,
    /// on every ARKit frame, also the ones not analyzed, so a face that ARKit
    /// loses and finds again between two analyzed frames is still checked
    /// against the depth. Returns the face track (`FaceFollower`).
    func followFaces(_ faces: [ARKitFace], depth data: AVDepthData?, image: ImageGeometry, at time: TimeInterval) -> UUID? {
        if let data {
            depth.ingest(data, at: time, image: image, horizontalFOVDegrees: nil, keepFull: keepsFullDepth)
        }
        return follower.arkitFrame(faces, hasNewDepth: data != nil, depth: &depth, at: time)
    }

    /// The full depth map is kept for liveness while recognition samples, and
    /// while a person is followed, whose face is looked for in it.
    private var keepsFullDepth: Bool {
        options.wantsEmbeddings || depth.people.person != nil
    }

    /// Looks for the face on the followed head in the depth map, every
    /// `depthFaceInterval`. When a depth signature is due, searches every new
    /// map for about a second and merges what it found into one signature.
    private func depthFace(in frame: SensorFrame, options: AnalyzerOptions) -> (face: DepthFace?, signature: DepthSignatureSample?) {
        let time = frame.timestamp
        guard frame.source == .trueDepth, let person = depth.people.person else {
            burst = nil
            return (nil, nil)
        }
        if let current = burst, current.person != person.id { burst = nil }
        if burst == nil, let interval = options.depthSignatureInterval, time - lastDepthSignature >= interval {
            burst = (person.id, time, [])
        }
        guard burst != nil || time - lastDepthFaceSearch >= depthFaceInterval,
              let mapTime = depth.full?.time, mapTime > lastDepthFaceMap else { return (nil, nil) }
        lastDepthFaceMap = mapTime
        lastDepthFaceSearch = time
        let face = depth.findFace(orientation: frame.orientation, at: time)
        lastDepthFace = (face, true)
        if face != nil { depthFaceFound = (time, person.id) }
        if options.isTracing {
            let text = face.map {
                String(format: "depth face at %.2fm, %d points, relief %.1f cm, coverage %.1f",
                       $0.noseMeters, $0.pointCount, $0.relief * 100, $0.coverage)
            } ?? "depth face not found on the followed head"
            depth.note(TraceNote(key: "depth face", text: text))
        }
        guard var current = burst else { return (face, nil) }
        // A face far from its resting expression changes shape, where ARKit can tell.
        if let face, (frame.faceExpression ?? 0) <= DepthSignature.maximumExpression {
            current.faces.append(face)
        }
        guard current.faces.count >= DepthFaceFusion.maximumFaces || time - current.startedAt >= burstSeconds else {
            burst = current
            return (face, nil)
        }
        burst = nil
        lastDepthSignature = time
        guard current.faces.count >= DepthFaceFusion.minimumFaces, let points = DepthFaceFusion.fuse(current.faces) else {
            if options.isTracing {
                depth.note(TraceNote(key: "depth signature", text: "depth signature skipped: \(current.faces.count) faces "
                    + "lined up in " + String(format: "%.2f", time - current.startedAt) + " s", repeats: true))
            }
            return (face, nil)
        }
        let sample = DepthSignatureSample(
            signature: DepthSignature(points: points), expression: frame.faceExpression,
            personID: person.id, faces: current.faces.count
        )
        return (face, sample)
    }

    /// Adds a line for the presence trace, delivered with the next analysis.
    func note(_ note: TraceNote) {
        depth.note(note)
    }

    func analyze(_ frame: SensorFrame, backend: BackendKind) -> FrameAnalysis {
        let options = self.options
        let time = frame.timestamp
        motion.pixelDelta = options.sensitivity.motionPixelDelta
        motion.areaFraction = options.sensitivity.motionAreaFraction

        var observation = SensorObservation(timestamp: Date(), source: frame.source)
        if let grid = LumaGrid.make(from: frame.pixelBuffer) {
            observation.motion = motion.process(grid)
        }
        observation.depthAgeSeconds = depth.lastArrival.map { time - $0 }
        var depthMoved = false
        // Depth arrives in its own callback, often just after the frame it belongs
        // to, so at 2 fps the newest map is usually the previous capture's.
        // Motion only compares maps with each other, so any new map will do.
        if backend == .depthScan, let result = depth.detectMotion(at: time) {
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
        let found = depthFace(in: frame, options: options)
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
        observation.isFreshSighting = !observation.faces.isEmpty || depthMoved || (humansDue && vision.humanCount > 0)
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

        if depth.people.person == nil { lastDepthFace = (nil, false) }
        let depthFaceSeen = depthFaceFound.map { time - $0.time <= 1 && $0.person == depth.people.person?.id } ?? false
        var debug: RecognitionDebugFrame?
        if options.wantsDebugView, time - lastDebugFrame >= debugInterval {
            lastDebugFrame = time
            let map = depth.full.flatMap { time - $0.time < 0.5 ? $0.map : nil } ?? depth.coarse?.map
            debug = debugRenderer.render(
                frame: frame, faces: observation.faces, map: map, person: depth.people.person,
                face: lastDepthFace.face, searched: lastDepthFace.searched
            )
            if let source = depth.lastSource {
                debug?.depthSource = "\(source.width)x\(source.height), smoothed by iOS \(source.filtered ? "yes" : "no")"
            }
        }

        return FrameAnalysis(
            observation: observation, embedding: embedding, handGesture: gesture, handSummary: handSummary,
            framesPerSecond: measureRate(at: time), backend: backend, faceTrackID: faceTrackID,
            traceNotes: depth.takeNotes(), depthSignature: found.signature, debug: debug, depthFaceSeen: depthFaceSeen
        )
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
