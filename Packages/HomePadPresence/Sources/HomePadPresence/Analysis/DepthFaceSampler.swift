import CoreGraphics
import Foundation
import ImageIO

/// The depth face of the followed person, map by map: where it is
/// (`DepthFaceDetector`), the face itself (`DepthFaceFinder`) and, when one is
/// due, a depth signature merged from the last few (`DepthFaceFusion`).
///
/// - Searches each new depth map while signatures are wanted, else every
///   `idleSearchInterval`.
/// - Looks only in a face box Vision found in the lit depth, or the last one
///   for `boxHold` while Vision misses a map. Around the followed head
///   instead, the crop landed on whatever the person was picked up from.
/// - Keeps the faces found on the person in the last `windowSeconds`, up to
///   `DepthFaceFusion.maximumFaces`. A signature merges them when it is due:
///   with an interval of 0 on every face found (depth deciding), else at
///   most every interval.
///
/// Runs on a queue of its own (`FrameAnalyzer`), never on the one face
/// tracking delivers frames to: there it held frames up, ARKit dropped them,
/// and their depth with them (2 maps a second instead of 4 to 6).
final class DepthFaceSampler {
    static let idleSearchInterval: TimeInterval = 0.5
    static let boxHold: TimeInterval = 1
    static let windowSeconds: TimeInterval = 3
    /// Seconds between search summaries in the trace.
    static let summaryInterval: TimeInterval = 10

    /// One depth map to look at.
    struct Job: @unchecked Sendable {
        var map: DepthMap
        var mapTime: TimeInterval
        var person: UUID
        /// Turns the map upright.
        var orientation: CGImagePropertyOrientation
        /// Nil while no signatures are wanted.
        var signatureInterval: TimeInterval?
        var time: TimeInterval
        var isTracing: Bool
    }

    /// What one map brought.
    struct Result: @unchecked Sendable {
        var face: DepthFace?
        /// Points of a depth signature, when one was due.
        var signature: [Float]?
        /// The roll Vision measured for the face in the lit depth, in degrees,
        /// for `UprightCalibration`.
        var roll: Double?
        /// The search and the lit depth, for the debug view. Nil when the
        /// map was not searched.
        var search: DepthFaceFinder.Search?
        var shaded: (image: CGImage, box: CGRect?)?
        /// Lines for the presence trace.
        var notes: [TraceNote] = []
    }

    private let detector = DepthFaceDetector()
    private var lastMapTime: TimeInterval = -.infinity
    private var lastSearchTime: TimeInterval = -.infinity
    private var lastSignatureTime: TimeInterval = -.infinity
    private var person: UUID?
    private var box: (rect: CGRect, time: TimeInterval)?
    private var window: [(time: TimeInterval, face: DepthFace)] = []
    /// Searches since the last summary: found, no face box, no face in the box.
    private var counts = (found: 0, noBox: 0, noFace: 0)
    private var lastSummaryTime: TimeInterval?

    /// Forgets everything, as when a backend starts or the depth turned.
    func reset() {
        lastMapTime = -.infinity
        lastSearchTime = -.infinity
        lastSignatureTime = -.infinity
        person = nil
        box = nil
        window.removeAll()
    }

    func process(_ job: Job) -> Result {
        if job.person != person {
            person = job.person
            box = nil
            window.removeAll()
        }
        let interval = job.signatureInterval == nil ? Self.idleSearchInterval : 0
        guard job.mapTime > lastMapTime, job.time - lastSearchTime >= interval else { return Result() }
        lastMapTime = job.mapTime
        lastSearchTime = job.time

        var result = search(job)
        if let face = result.face {
            window.append((job.time, face))
            window.removeAll { job.time - $0.time > Self.windowSeconds }
            if window.count > DepthFaceFusion.maximumFaces { window.removeFirst(window.count - DepthFaceFusion.maximumFaces) }
            if let interval = job.signatureInterval, window.count >= DepthFaceFusion.minimumFaces,
               job.time - lastSignatureTime >= interval,
               let points = DepthFaceFusion.fuse(window.map(\.face)) {
                lastSignatureTime = job.time
                result.signature = points
            }
        }
        if job.isTracing { result.notes = notes(for: result, at: job.time) }
        return result
    }

    /// The face box from the lit depth (or the one held), and the face in it.
    private func search(_ job: Job) -> Result {
        let detection = detector.detect(in: job.map, orientation: job.orientation)
        if let found = detection.face { box = (found.box, job.time) }
        var result = Result(roll: detection.face?.rollDegrees, shaded: detection.shaded.map { ($0, detection.face?.box) })
        guard let box, job.time - box.time <= Self.boxHold else {
            counts.noBox += 1
            result.search = DepthFaceFinder.Search(miss: "no face in the lit depth")
            return result
        }
        let search = DepthFaceFinder.search(in: job.map, faceBox: box.rect, orientation: job.orientation)
        result.search = search
        result.face = search.face
        if search.face == nil { counts.noFace += 1 } else { counts.found += 1 }
        return result
    }

    /// The search's line, and every `summaryInterval` what the searches came to.
    private func notes(for result: Result, at time: TimeInterval) -> [TraceNote] {
        var notes: [TraceNote] = []
        if let search = result.search {
            let text = search.face.map {
                String(format: "depth face at %.2fm, %d points, relief %.1f cm, coverage %.2f",
                       $0.noseMeters, $0.pointCount, $0.relief * 100, $0.coverage)
            } ?? "depth face not found: \(search.miss ?? "?")"
            notes.append(TraceNote(key: "depth face", text: text))
        }
        let since = lastSummaryTime ?? time
        if lastSummaryTime == nil { lastSummaryTime = time }
        if time - since >= Self.summaryInterval {
            if counts.found + counts.noBox + counts.noFace > 0 {
                notes.append(TraceNote(key: "depth face searches", text: "depth face searches in "
                    + String(format: "%.0f s: ", time - since)
                    + "\(counts.found) found, \(counts.noBox) with no face box, \(counts.noFace) with no face in the box",
                    repeats: true))
            }
            counts = (0, 0, 0)
            lastSummaryTime = time
        }
        return notes
    }
}
