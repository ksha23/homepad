@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import simd

/// How the camera image of a frame was taken, for lining its depth up with it.
struct ImageGeometry: Sendable {
    /// Native image size in pixels.
    var size: CGSize
    /// The image's intrinsic matrix (ARKit), nil when unknown.
    var intrinsics: simd_float3x3?
}

/// A face ARKit tracks, as the depth person tracker needs it.
struct FaceInImage: Equatable, Sendable {
    /// The face's center in the native image, normalized with a top-left origin.
    var point: CGPoint
    /// ARKit's distance to the face along the camera axis, in meters.
    var distanceMeters: Double
}

/// A line for the presence trace, logged when it changes under its key, or
/// every time when it `repeats`.
struct TraceNote: Equatable, Sendable {
    var key: String
    var text: String
    var repeats = false
}

/// The analyzer's depth: the newest maps, movement in them, and the person
/// followed through them (`DepthPersonTracker`).
///
/// Every depth map is read into a coarse map of about 48 columns, a few
/// thousand reads, for presence and motion. The full map is copied only while
/// recognition wants samples, for the liveness check.
///
/// Used on the analysis queue only.
struct DepthSensing {
    static let coarseColumns = 48

    /// Full resolution, for the liveness check.
    private(set) var full: (map: DepthMap, time: TimeInterval)?
    /// Coarse, for presence and motion.
    private(set) var coarse: (map: DepthMap, time: TimeInterval)?
    /// Capture time of the newest depth data, for the trace.
    private(set) var lastArrival: TimeInterval?
    /// The newest depth's native size and whether iOS had already smoothed
    /// and filled it in, for the recognition debug view.
    private(set) var lastSource: (width: Int, height: Int, filtered: Bool)?
    private(set) var people = DepthPersonTracker()
    private var motion = DepthMotionDetector()
    /// Capture time of the last map the motion detector compared.
    private var lastMotionTime: TimeInterval = -.infinity
    private var notes: [TraceNote] = []
    /// How faces are turned on their way into the depth map (`FaceFlip`).
    private(set) var flip = FaceFlip.none
    /// Another flip that alone found the face, and on how many maps in a row.
    private var flipHits: (flip: FaceFlip, count: Int)?
    /// Maps in a row another flip must find the face on before it is used.
    static let flipHitsToSwitch = 5
    /// The alignment line, and when it was last written. It is written again
    /// when it changes, when a backend starts and every `alignmentInterval`,
    /// so a trace that keeps only its newest part still has it.
    private var alignment: (text: String, notedAt: TimeInterval)?
    static let alignmentInterval: TimeInterval = 3600
    /// How old a depth map may be for a face Vision found to be checked against it.
    static let visionFaceMaxAge: TimeInterval = 0.5

    // MARK: Depth in

    /// Reads one depth map. `image` lines it up with an ARKit image, and
    /// `horizontalFOVDegrees` gives AVCapture depth, which matches its video,
    /// its scale.
    mutating func ingest(
        _ depth: AVDepthData, at time: TimeInterval, image: ImageGeometry?, horizontalFOVDegrees: Double?, keepFull: Bool
    ) {
        lastArrival = time
        lastSource = (CVPixelBufferGetWidth(depth.depthDataMap), CVPixelBufferGetHeight(depth.depthDataMap), depth.isDepthDataFiltered)
        let alignment = Self.alignment(of: depth, image: image, horizontalFOVDegrees: horizontalFOVDegrees)
        if keepFull, var map = DepthMap(depth) {
            map.registration = alignment.registration
            map.focalLength = alignment.focalLength
            full = (map, time)
            coarse = (map.downsampled(step: map.step(toColumns: Self.coarseColumns)), time)
        } else {
            let step = max(1, CVPixelBufferGetWidth(depth.depthDataMap) / Self.coarseColumns)
            guard var map = DepthMap(depth, step: step) else { return }
            map.registration = alignment.registration
            map.focalLength = alignment.focalLength.map { $0 / Double(step) }
            ingest(coarse: map, at: time)
        }
        if let note = alignment.note { noteAlignment(note, at: time) }
    }

    /// Writes the alignment line again with the next depth map, as when a
    /// backend starts.
    mutating func noteAlignmentAgain() {
        alignment = nil
    }

    /// Writes the alignment line when it changed, after `noteAlignmentAgain`,
    /// or `alignmentInterval` after it was last written.
    mutating func noteAlignment(_ text: String, at time: TimeInterval) {
        if let alignment, alignment.text == text, time - alignment.notedAt < Self.alignmentInterval { return }
        alignment = (text, time)
        notes.append(TraceNote(key: "depth alignment", text: text, repeats: true))
    }

    /// Takes a coarse map that is already read, for presence and motion only.
    mutating func ingest(coarse map: DepthMap, at time: TimeInterval) {
        lastArrival = time
        coarse = (map, time)
    }

    /// The full map when it is no older than `maxAge` at `time`.
    func fullMap(at time: TimeInterval, maxAge: TimeInterval) -> DepthMap? {
        full.flatMap { time - $0.time < maxAge ? $0.map : nil }
    }

    // MARK: People

    /// Follows the person on an ARKit frame, after its depth (if any) was
    /// ingested. Faces seed or confirm them. Returns the followed person's ID
    /// when the faces belong to them, or when no face is in view.
    mutating func follow(_ faces: [FaceInImage], hasNewDepth: Bool, at time: TimeInterval) -> UUID? {
        let seeds = seeds(for: faces, flip: flip)
        if hasNewDepth, let coarse {
            let before = people
            people.update(coarse.map, seeds: seeds, at: time)
            noteEvents()
            if !faces.isEmpty { checkFlip(before: before, map: coarse.map, faces: faces, at: time) }
            return people.person?.id
        }
        // No depth on this frame: a face confirms the person when it is on their head.
        people.expire(at: time)
        noteEvents()
        guard let person = people.person else { return nil }
        if seeds.isEmpty { return person.id }
        for seed in seeds where people.confirm(face: seed.point, at: time) {
            return person.id
        }
        return nil
    }

    /// A face Vision found on a frame where ARKit tracks none, at `point` in
    /// the native image (normalized, top-left origin), about `expectedMeters`
    /// away by its size. It seeds or confirms the depth person exactly like an
    /// ARKit face: through the registration into the newest depth map, at the
    /// depth measured there. Vision's box is turned back to the native image
    /// by the frame's own orientation, so no `FaceFlip` applies.
    mutating func followVisionFace(at point: CGPoint, expectedMeters: Double?, at time: TimeInterval) -> FaceTrackContinuity.VisionFaceDepth {
        guard let coarse, time - coarse.time <= Self.visionFaceMaxAge else { return .unknown }
        let registration = coarse.map.registration ?? .identity
        let depthPoint = registration.depthPoint(fromImage: point)
        let followed = people.person
        people.update(coarse.map, seeds: [DepthPersonTracker.Seed(point: depthPoint, expectedMeters: expectedMeters)], at: time)
        noteEvents()
        if !people.missedSeed, let person = people.person { return .person(person.id) }
        // Nothing usable under the face. Off the followed head, it is someone else.
        if let followed, !people.isOnHead(depthPoint, of: followed) { return .elsewhere }
        return .unknown
    }

    /// Runs the motion detector on a new coarse map, and picks up or follows
    /// the person from the moving patch (the depth scan).
    mutating func detectMotion(at time: TimeInterval) -> DepthMotionDetector.Result? {
        guard let latest = coarse, latest.time > lastMotionTime, time - latest.time < 1 else { return nil }
        lastMotionTime = latest.time
        let result = motion.process(latest.map)
        let seeds = result.nearestPoint.map { [DepthPersonTracker.Seed(point: $0, expectedMeters: nil)] } ?? []
        people.update(latest.map, seeds: seeds, at: latest.time)
        noteEvents()
        return result
    }

    /// The face on the followed person's head in the newest full map, found
    /// by depth alone (`DepthFaceFinder`), when that map is fresh. A face found
    /// there confirms the person, as a face from ARKit or Vision does: in the
    /// dark nothing else did while they sat still, and they were let go after
    /// `DepthPersonTracker.Config.holdSeconds`.
    /// Nil when there is no full map or no followed head in it to look at,
    /// which is no search at all.
    mutating func findFace(orientation: CGImagePropertyOrientation, at time: TimeInterval) -> DepthFaceFinder.Search? {
        guard let full, let person = people.person, full.time - person.seenAt <= 1 else { return nil }
        let search = DepthFaceFinder.search(in: full.map, head: person, orientation: orientation)
        if let face = search.face { people.confirm(face: face.nosePoint, at: full.time) }
        return search
    }

    /// The followed person, when the depth showed them in the last second.
    func person(at time: TimeInterval) -> DepthPersonTracker.Person? {
        people.person.flatMap { time - $0.seenAt <= 1 ? $0 : nil }
    }

    /// Adds a line for the presence trace.
    mutating func note(_ note: TraceNote) {
        notes.append(note)
    }

    /// Trace lines since the last call.
    mutating func takeNotes() -> [TraceNote] {
        defer { notes.removeAll() }
        return notes
    }

    mutating func reset() {
        full = nil
        coarse = nil
        lastArrival = nil
        people.reset()
        motion.reset()
        lastMotionTime = -.infinity
        notes.removeAll()
        flipHits = nil
        alignment = nil
    }

    // MARK: Private

    /// When the face missed itself in the depth map, tries the other flips on
    /// the map as it was before. One that alone finds the face five maps in a
    /// row is used from then on (`FaceFlip`).
    private mutating func checkFlip(before: DepthPersonTracker, map: DepthMap, faces: [FaceInImage], at time: TimeInterval) {
        guard people.missedSeed else {
            flipHits = nil
            return
        }
        for candidate in FaceFlip.allCases where candidate != flip {
            var trial = before
            trial.update(map, seeds: seeds(for: faces, flip: candidate), at: time)
            guard !trial.missedSeed else { continue }
            let count = flipHits?.flip == candidate ? (flipHits?.count ?? 0) + 1 : 1
            flipHits = (candidate, count)
            if count >= Self.flipHitsToSwitch {
                flip = candidate
                people = trial
                flipHits = nil
                noteEvents()
                notes.append(TraceNote(key: "depth flip", text: "faces were found in the depth map only "
                    + "\(candidate.title), \(Self.flipHitsToSwitch) maps in a row: using that from now on"))
            }
            return
        }
        flipHits = nil
    }

    /// Faces as seeds in the coarse map, nearest first.
    private func seeds(for faces: [FaceInImage], flip: FaceFlip) -> [DepthPersonTracker.Seed] {
        let registration = coarse?.map.registration ?? .identity
        return faces.sorted { $0.distanceMeters < $1.distanceMeters }.map { face in
            let point = registration.depthPoint(fromImage: flip.apply(face.point))
            return DepthPersonTracker.Seed(point: point, expectedMeters: face.distanceMeters)
        }
    }

    private mutating func noteEvents() {
        for event in people.events {
            notes.append(Self.note(for: event))
        }
    }

    private static func note(for event: DepthPersonTracker.Event) -> TraceNote {
        switch event {
        case .started(let person, let fromFace):
            TraceNote(key: "depth person", text: "depth person \(short(person.id)) started at \(meters(person.distanceMeters)) "
                + "from \(fromFace ? "a face" : "movement")")
        case .seedMissed(let surface, let expected):
            TraceNote(key: "depth seed", text: "depth seed missed: surface \(surface.map(meters) ?? "none"), "
                + "face \(expected.map(meters) ?? "-")")
        case .lost(let person):
            TraceNote(key: "depth person", text: "depth person \(short(person.id)) lost at \(meters(person.distanceMeters))")
        case .letGo(let person):
            TraceNote(key: "depth person", text: "depth person \(short(person.id)) let go: no face or movement "
                + "for \(Int(DepthPersonTracker.Config().holdSeconds)) s")
        }
    }

    static func meters(_ value: Double) -> String { String(format: "%.1fm", value) }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(4)) }
}

extension DepthSensing {
    /// How a depth map lines up with its image, its focal length in its own
    /// pixels, and a trace line describing both.
    struct Alignment {
        var registration: DepthRegistration?
        var focalLength: Double?
        var note: String?
    }

    /// With ARKit's image intrinsics and the depth's own calibration the
    /// registration is exact. Without calibration the image is taken as the
    /// centered crop of the depth map. AVCapture depth matches its video, so
    /// only its scale comes from the video's field of view.
    static func alignment(of depth: AVDepthData, image: ImageGeometry?, horizontalFOVDegrees: Double?) -> Alignment {
        let buffer = depth.depthDataMap
        let depthSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        guard let image, let matrix = image.intrinsics else {
            let focal = horizontalFOVDegrees.flatMap {
                ProximityMath.focalLengthPixels(imageWidth: Double(depthSize.width), horizontalFOVDegrees: $0)
            }
            return Alignment(registration: nil, focalLength: focal, note: nil)
        }
        let imagePinhole = PinholeIntrinsics(matrix: matrix, size: image.size)
        let registration: DepthRegistration
        let focal: Double
        if let calibration = depth.cameraCalibrationData {
            let reference = PinholeIntrinsics(matrix: calibration.intrinsicMatrix, size: calibration.intrinsicMatrixReferenceDimensions)
            registration = DepthRegistration(image: imagePinhole, depth: reference)
            focal = reference.focalX * Double(depthSize.width) / reference.width
        } else {
            registration = DepthRegistration(imageSize: image.size, depthSize: depthSize)
            focal = imagePinhole.focalX * registration.scaleX * Double(depthSize.width) / Double(image.size.width)
        }
        let note = "depth map \(Int(depthSize.width))x\(Int(depthSize.height)) for image "
            + "\(Int(image.size.width))x\(Int(image.size.height)), calibration \(depth.cameraCalibrationData != nil ? "yes" : "no"), "
            + "\(registration.summary), focal \(Int(focal.rounded())) px"
        return Alignment(registration: registration, focalLength: focal, note: note)
    }
}
