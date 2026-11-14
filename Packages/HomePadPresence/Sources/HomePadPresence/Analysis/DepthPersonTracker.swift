import CoreGraphics
import Foundation

/// Follows one person from one TrueDepth depth map to the next, while their
/// face comes and goes.
///
/// In a dark room ARKit loses a tracked face on about half the frames, often
/// for seconds, while the depth map still shows the head where the face was.
/// A person is picked up from a seed (a face ARKit tracks, or a patch of depth
/// that moved) and followed while a head-sized surface stays near where they
/// were, at about the same depth.
///
/// - The room never starts a person. Only a face or movement does, so the
///   walls and furniture a wall-mounted iPad always sees do not count.
/// - A person standing still stays followed. Nothing needs to move.
/// - Movement beside a face seen in the last `faceHoldSeconds` is that
///   person moving and picks no one up.
/// - Something right behind them, such as a chair back within 15 cm of their
///   head, can take their place when they leave. That is why a person is let
///   go `holdSeconds` after a face, or their own movement, last confirmed them.
///
/// Points are normalized with a top-left origin in the native depth map.
/// Used on the analysis queue only.
struct DepthPersonTracker: Sendable {
    struct Config: Equatable, Sendable {
        /// Half the width of a head, in meters.
        var headRadiusMeters = 0.12
        /// How fast a head may move between two depth maps, in meters a second.
        var speedMetersPerSecond = 1.5
        /// How far a head may move between two depth maps at least, in meters.
        var minimumStepMeters = 0.15
        /// And at most, so a long wait for depth does not search the whole room.
        var maximumStepMeters = 0.6
        /// How far behind the nearest point of a face the face still is, in meters.
        var faceDepthMeters = 0.06
        /// A face this far from the followed head, sideways or in depth, is someone else.
        var sameHeadMeters = 0.2
        /// A seed whose surface is this far from ARKit's distance for the face
        /// did not land on the face. Generous, since ARKit misjudges the
        /// distance of a face in the dark.
        var seedToleranceMeters = 0.8
        /// Moving this far confirms that a followed person is still there.
        var movementMeters = 0.2
        /// How long a person is followed without a face or movement confirming them.
        var holdSeconds: TimeInterval = 30
        /// While a face confirmed the person this recently, movement picks no
        /// one up: movement beside a face in view is that person moving, a
        /// hand or a shoulder. In the dark it took the person off their face
        /// onto their body every few seconds (a new person at 0.7 m while the
        /// face was still found at 0.57 m), and recognition started over each time.
        var faceHoldSeconds: TimeInterval = 3
    }

    /// Where to pick a person up.
    struct Seed: Equatable, Sendable {
        var point: CGPoint
        /// ARKit's distance for the face along the camera axis, nil for movement.
        var expectedMeters: Double?
    }

    /// The person being followed.
    struct Person: Equatable, Sendable {
        /// The same while the same person is followed.
        var id: UUID
        /// Center of the head in the depth map.
        var center: CGPoint
        /// Depth of the head, in meters.
        var distanceMeters: Double
        /// Head radius in normalized units of the depth map.
        var radius: CGSize
        /// When a face or movement last confirmed them, and where they were then.
        var confirmedAt: TimeInterval
        var confirmedCenter: CGPoint
        var confirmedDistance: Double
        /// When a face last confirmed them, nil if only movement has.
        var faceSeenAt: TimeInterval?
        /// When the depth last showed them.
        var seenAt: TimeInterval
    }

    /// Something worth a line in the presence trace.
    enum Event: Equatable, Sendable {
        case started(Person, fromFace: Bool)
        case seedMissed(surfaceMeters: Double?, expectedMeters: Double?)
        case lost(Person)
        case letGo(Person)
    }

    var config = Config()
    private(set) var person: Person?
    /// What changed on the last update or confirmation, for the trace.
    private(set) var events: [Event] = []

    /// True when the last update had a seed that did not land on anything.
    var missedSeed: Bool {
        events.contains { event in
            if case .seedMissed = event { return true }
            return false
        }
    }

    /// Notes one depth map. `seeds` are faces or moving patches, nearest first.
    /// Returns the person followed after it.
    @discardableResult
    mutating func update(_ map: DepthMap, seeds: [Seed], at time: TimeInterval) -> Person? {
        events.removeAll()
        if let seed = seeds.first, !isMovementBesideFace(seed, at: time) {
            switch locateSeed(seed, in: map) {
            case .found(let head):
                adopt(head, in: map, fromFace: seed.expectedMeters != nil, at: time)
                return person
            case .missed(let surface):
                events.append(.seedMissed(surfaceMeters: surface, expectedMeters: seed.expectedMeters))
            }
        }
        follow(in: map, at: time)
        return person
    }

    /// A face seen on a frame without depth confirms the person when it is on
    /// their head. Returns true when it was.
    @discardableResult
    mutating func confirm(face point: CGPoint, at time: TimeInterval) -> Bool {
        events.removeAll()
        guard var current = person, isOnHead(point, of: current) else { return false }
        current.faceSeenAt = time
        current.confirmedAt = time
        current.confirmedCenter = current.center
        current.confirmedDistance = current.distanceMeters
        person = current
        return true
    }

    /// True when `point` lies on the followed person's head, give or take a head.
    func isOnHead(_ point: CGPoint, of person: Person) -> Bool {
        let dx = (point.x - person.center.x) / max(person.radius.width * 2, 0.001)
        let dy = (point.y - person.center.y) / max(person.radius.height * 2, 0.001)
        return dx * dx + dy * dy <= 1
    }

    /// Lets go of the person once nothing confirmed them for `holdSeconds`.
    mutating func expire(at time: TimeInterval) {
        events.removeAll()
        letGoIfStale(at: time)
    }

    private mutating func letGoIfStale(at time: TimeInterval) {
        guard let current = person, time - current.confirmedAt > config.holdSeconds else { return }
        events.append(.letGo(current))
        person = nil
    }

    mutating func reset() {
        person = nil
        events.removeAll()
    }

    // MARK: Following

    private struct Head {
        var center: CGPoint
        var distance: Double
        var radius: CGSize
    }

    /// A movement seed while a face confirmed the followed person in the last `faceHoldSeconds`.
    private func isMovementBesideFace(_ seed: Seed, at time: TimeInterval) -> Bool {
        guard seed.expectedMeters == nil, let faceSeenAt = person?.faceSeenAt else { return false }
        return time - faceSeenAt <= config.faceHoldSeconds
    }

    /// A face, or movement, picks up a person, or confirms the one followed.
    private mutating func adopt(_ head: Head, in map: DepthMap, fromFace: Bool, at time: TimeInterval) {
        let previous = person
        let same = previous.map { isSame(head, as: $0, in: map, at: time) } ?? false
        let faceSeenAt = fromFace ? time : (same ? previous?.faceSeenAt : nil)
        let next = Person(
            id: same ? previous?.id ?? UUID() : UUID(), center: head.center, distanceMeters: head.distance,
            radius: head.radius, confirmedAt: time, confirmedCenter: head.center, confirmedDistance: head.distance,
            faceSeenAt: faceSeenAt, seenAt: time
        )
        if let previous, !same { events.append(.lost(previous)) }
        if !same { events.append(.started(next, fromFace: fromFace)) }
        person = next
    }

    /// Finds the followed head again near where it was.
    private mutating func follow(in map: DepthMap, at time: TimeInterval) {
        guard var current = person else { return }
        letGoIfStale(at: time)
        guard person != nil else { return }
        let elapsed = max(0, time - current.seenAt)
        let step = min(config.maximumStepMeters, max(config.minimumStepMeters, config.speedMetersPerSecond * elapsed))
        guard let head = locateHead(near: current.center, at: current.distanceMeters, within: step, in: map) else {
            events.append(.lost(current))
            person = nil
            return
        }
        current.center = head.center
        current.distanceMeters = head.distance
        current.radius = head.radius
        current.seenAt = time
        if moved(current, in: map) {
            current.confirmedAt = time
            current.confirmedCenter = current.center
            current.confirmedDistance = current.distanceMeters
        }
        person = current
    }

    private func isSame(_ head: Head, as person: Person, in map: DepthMap, at time: TimeInterval) -> Bool {
        let moved = min(config.maximumStepMeters, config.speedMetersPerSecond * max(0, time - person.seenAt))
        let allowance = config.sameHeadMeters + moved
        let sideways = metersBetween(head.center, person.center, at: head.distance, in: map)
        return sideways <= allowance && abs(head.distance - person.distanceMeters) <= allowance
    }

    private func moved(_ person: Person, in map: DepthMap) -> Bool {
        let sideways = metersBetween(person.center, person.confirmedCenter, at: person.distanceMeters, in: map)
        let depth = abs(person.distanceMeters - person.confirmedDistance)
        return max(sideways, depth) >= config.movementMeters
    }

    // MARK: Locating a head

    private enum SeedResult {
        case found(Head)
        /// Nothing usable there, or a surface too far from ARKit's distance.
        case missed(surface: Double?)
    }

    /// The face at a seed: the nearest surface within a head's radius of it.
    private func locateSeed(_ seed: Seed, in map: DepthMap) -> SeedResult {
        let guess = seed.expectedMeters ?? Double(cellDepth(at: seed.point, in: map) ?? 1)
        let cells = cellsAround(seed.point, radiusMeters: config.headRadiusMeters, at: guess, in: map)
        guard let nearest = percentile(cells.map(\.depth), 0.1) else { return .missed(surface: nil) }
        // The face is the front of the head: its relief is a few centimeters,
        // and the body below it is farther.
        let head = cells.filter { $0.depth <= nearest + config.faceDepthMeters }
        guard let found = makeHead(head, in: map) else { return .missed(surface: nil) }
        if let expected = seed.expectedMeters, abs(found.distance - expected) > config.seedToleranceMeters {
            return .missed(surface: found.distance)
        }
        return .found(found)
    }

    /// The head near `center`, at about the same depth as before.
    ///
    /// While most of the head's disk is still at the head's depth, the center
    /// stays put. Re-centering on every map let it creep down onto the body
    /// of someone standing still, and their face, back after a gap, then
    /// looked like someone else's. Only a head that moved is looked for again,
    /// within `step` of where it was.
    private func locateHead(near center: CGPoint, at distance: Double, within step: Double, in map: DepthMap) -> Head? {
        let band = max(config.minimumStepMeters, step)
        let disk = cellsAround(center, radiusMeters: config.headRadiusMeters, at: distance, in: map)
        let stayed = disk.filter { abs($0.depth - distance) <= band }
        if !stayed.isEmpty, stayed.count * 2 >= disk.count {
            return makeHead(stayed, center: center, in: map)
        }
        let around = cellsAround(center, radiusMeters: config.headRadiusMeters + step, at: distance, in: map)
            .filter { abs($0.depth - distance) <= band }
        guard let closest = around.min(by: { squaredPixels($0.point, center, map) < squaredPixels($1.point, center, map) }) else {
            return nil
        }
        let headRadius = config.headRadiusMeters * pixelsPerMeter(at: distance, in: map)
        let head = around.filter { squaredPixels($0.point, closest.point, map) <= headRadius * headRadius + 0.5 }
        return makeHead(head, in: map)
    }

    /// A head from its cells: their median depth, centered on `center` or on the cells.
    private func makeHead(_ cells: [Cell], center: CGPoint? = nil, in map: DepthMap) -> Head? {
        guard !cells.isEmpty, let distance = percentile(cells.map(\.depth), 0.5) else { return nil }
        let x = cells.map { Double($0.point.x) }.reduce(0, +) / Double(cells.count)
        let y = cells.map { Double($0.point.y) }.reduce(0, +) / Double(cells.count)
        let radiusPixels = max(1, config.headRadiusMeters * pixelsPerMeter(at: distance, in: map))
        let radius = CGSize(width: radiusPixels / Double(map.width), height: radiusPixels / Double(map.height))
        return Head(center: center ?? CGPoint(x: x, y: y), distance: distance, radius: radius)
    }

    // MARK: Cells

    private struct Cell {
        var point: CGPoint
        var depth: Double
    }

    /// Cells with depth within `radiusMeters` of `center`, for a surface `distance` away.
    private func cellsAround(_ center: CGPoint, radiusMeters: Double, at distance: Double, in map: DepthMap) -> [Cell] {
        let radius = max(1, radiusMeters * pixelsPerMeter(at: distance, in: map))
        let centerColumn = Double(center.x) * Double(map.width)
        let centerRow = Double(center.y) * Double(map.height)
        let columns = Int((centerColumn - radius).rounded(.down))...Int((centerColumn + radius).rounded(.up))
        let rows = Int((centerRow - radius).rounded(.down))...Int((centerRow + radius).rounded(.up))
        var cells: [Cell] = []
        for row in rows {
            for column in columns {
                let dx = Double(column) + 0.5 - centerColumn
                let dy = Double(row) + 0.5 - centerRow
                guard dx * dx + dy * dy <= radius * radius else { continue }
                let depth = map.depth(column: column, row: row)
                guard depth.isFinite else { continue }
                let point = CGPoint(x: (Double(column) + 0.5) / Double(map.width), y: (Double(row) + 0.5) / Double(map.height))
                cells.append(Cell(point: point, depth: Double(depth)))
            }
        }
        return cells
    }

    private func cellDepth(at point: CGPoint, in map: DepthMap) -> Float? {
        let depth = map.depth(column: Int(Double(point.x) * Double(map.width)), row: Int(Double(point.y) * Double(map.height)))
        return depth.isFinite ? depth : nil
    }

    /// Map pixels a meter wide object covers at `distance`.
    private func pixelsPerMeter(at distance: Double, in map: DepthMap) -> Double {
        map.focalLengthOrDefault / max(distance, 0.1)
    }

    private func squaredPixels(_ a: CGPoint, _ b: CGPoint, _ map: DepthMap) -> Double {
        let dx = Double(a.x - b.x) * Double(map.width)
        let dy = Double(a.y - b.y) * Double(map.height)
        return dx * dx + dy * dy
    }

    private func metersBetween(_ a: CGPoint, _ b: CGPoint, at distance: Double, in map: DepthMap) -> Double {
        squaredPixels(a, b, map).squareRoot() / pixelsPerMeter(at: distance, in: map)
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[Int(Double(sorted.count - 1) * fraction)]
    }
}
