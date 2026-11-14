import CoreGraphics
import Foundation
import ImageIO

/// The depth face of the followed person, frame by frame, for the analyzer:
/// where it is (`DepthFaceDetector`), the face itself (`DepthFaceFinder`) and,
/// when one is due, a depth signature merged from the last few
/// (`DepthFaceFusion`).
///
/// - Searches each new depth map while signatures are wanted, else every
///   `idleSearchInterval`.
/// - Looks only in a face box Vision found in the lit depth, or the last one
///   for `boxHold` while Vision misses a map. Around the followed head
///   instead, the crop landed on whatever the person was picked up from.
/// - Keeps the faces found on the person in the last `windowSeconds`, up to
///   `DepthFaceFusion.maximumFaces`. A signature merges them when it is due:
///   with an interval of 0 on every face found (depth deciding in the dark),
///   else at most every interval.
///
/// Used on the analysis queue only.
final class DepthFaceSampler {
    static let idleSearchInterval: TimeInterval = 0.5
    static let boxHold: TimeInterval = 1
    static let windowSeconds: TimeInterval = 3
    /// A face found on the person stays in view this long, so a few searches
    /// that miss do not end the look and its votes.
    static let faceHold: TimeInterval = 10
    /// Seconds between search summaries in the trace.
    static let summaryInterval: TimeInterval = 10

    /// What one frame brought.
    struct Result {
        var face: DepthFace?
        /// Points of a depth signature, when one was due.
        var signature: [Float]?
        /// The roll Vision measured for the face in the lit depth, in degrees,
        /// for `UprightCalibration`.
        var roll: Double?
    }

    private let detector = DepthFaceDetector()
    private var lastMapTime: TimeInterval = -.infinity
    private var lastSearchTime: TimeInterval = -.infinity
    private var lastSignatureTime: TimeInterval = -.infinity
    private var person: UUID?
    private var box: (rect: CGRect, time: TimeInterval)?
    private var window: [(time: TimeInterval, face: DepthFace)] = []
    private var lastFoundTime: TimeInterval?
    /// Searches since the last summary: found, no face box, no face in the box.
    private var counts = (found: 0, noBox: 0, noFace: 0)
    private var lastSummaryTime: TimeInterval?

    /// The last search and lit depth, for the debug view.
    private(set) var lastSearch: DepthFaceFinder.Search?
    private(set) var lastShaded: (image: CGImage, box: CGRect?)?

    /// Forgets everything, as when a backend starts or the depth turned.
    func reset() {
        lastMapTime = -.infinity
        lastSearchTime = -.infinity
        lastSignatureTime = -.infinity
        person = nil
        box = nil
        window.removeAll()
        lastFoundTime = nil
        lastSearch = nil
        lastShaded = nil
    }

    /// True while a face was found on `person` in the last `faceHold`.
    func isFaceInView(on person: UUID?, at time: TimeInterval) -> Bool {
        guard let person, person == self.person, let found = lastFoundTime else { return false }
        return time - found <= Self.faceHold
    }

    /// One frame. `map` is the newest full depth map and its capture time,
    /// `person` the followed person, `orientation` turns the map upright, and
    /// `signatureInterval` is nil while no signatures are wanted.
    func process(
        map: (map: DepthMap, time: TimeInterval)?, person: UUID?, orientation: CGImagePropertyOrientation,
        signatureInterval: TimeInterval?, at time: TimeInterval
    ) -> Result {
        guard let person else {
            forgetPerson()
            return Result()
        }
        if person != self.person {
            forgetPerson()
            self.person = person
        }
        let interval = signatureInterval == nil ? Self.idleSearchInterval : 0
        guard let map, map.time > lastMapTime, time - lastSearchTime >= interval else { return Result() }
        lastMapTime = map.time
        lastSearchTime = time

        let detection = detector.detect(in: map.map, orientation: orientation)
        lastShaded = detection.shaded.map { ($0, detection.face?.box) }
        if let found = detection.face { box = (found.box, time) }
        var result = Result(roll: detection.face?.rollDegrees)
        guard let box, time - box.time <= Self.boxHold else {
            counts.noBox += 1
            lastSearch = DepthFaceFinder.Search(miss: "no face in the lit depth")
            return result
        }
        let search = DepthFaceFinder.search(in: map.map, faceBox: box.rect, orientation: orientation)
        lastSearch = search
        guard let face = search.face else {
            counts.noFace += 1
            return result
        }
        counts.found += 1
        lastFoundTime = time
        result.face = face
        window.append((time, face))
        window.removeAll { time - $0.time > Self.windowSeconds }
        if window.count > DepthFaceFusion.maximumFaces { window.removeFirst(window.count - DepthFaceFusion.maximumFaces) }
        if let signatureInterval, window.count >= DepthFaceFusion.minimumFaces,
           time - lastSignatureTime >= signatureInterval,
           let points = DepthFaceFusion.fuse(window.map(\.face)) {
            lastSignatureTime = time
            result.signature = points
        }
        return result
    }

    /// Lines for the trace: the last search, and every `summaryInterval` what
    /// the searches came to.
    func traceNotes(at time: TimeInterval) -> [TraceNote] {
        var notes: [TraceNote] = []
        if let search = lastSearch {
            let text = search.face.map {
                String(format: "depth face at %.2fm, %d points, relief %.1f cm, coverage %.2f",
                       $0.noseMeters, $0.pointCount, $0.relief * 100, $0.coverage)
            } ?? "depth face not found: \(search.miss ?? "?")"
            notes.append(TraceNote(key: "depth face", text: text))
        }
        let since = lastSummaryTime ?? time
        if lastSummaryTime == nil { lastSummaryTime = time }
        if time - since >= Self.summaryInterval {
            let total = counts.found + counts.noBox + counts.noFace
            if total > 0 {
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

    private func forgetPerson() {
        person = nil
        box = nil
        window.removeAll()
        lastFoundTime = nil
    }
}
