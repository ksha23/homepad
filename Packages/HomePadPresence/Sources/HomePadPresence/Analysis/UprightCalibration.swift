import Foundation
import ImageIO

/// How many quarter turns to add to a backend's orientation so its frames
/// stand upright, learned from the faces in them.
///
/// The rotation coordinator's angle is for AVCapture's native buffer, and
/// ARKit's captured image does not always share that layout. On the 11-inch
/// on a stand in landscape the coordinator said 180, the frames were turned
/// upside down, and Vision found faces in them at a roll of -122 to -170
/// degrees: they needed no turn at all. Faces are what must stand upright,
/// so they decide, on any iPad and wherever its camera sits. The last
/// `samplesNeeded` rolls of a backend and orientation are averaged as
/// angles. When they agree (`minimumAgreement`) and the average rounds to a
/// turn, it is kept in the settings for that backend and orientation from
/// then on. Heads tilt: those rolls ran 10 to 58 degrees off a half turn, so
/// rounding each on its own split them between two turns.
///
/// Used on the analysis queue only.
struct UprightCalibration {
    static let samplesNeeded = 5
    /// Length of the rolls' mean direction, 0 when they point every way and
    /// 1 when they all point the same way.
    static let minimumAgreement = 0.75
    private static let defaultsPrefix = "presence.upright."

    /// Quarter turns clockwise, by `key`.
    private var turns: [String: Int] = [:]
    private var rolls: [String: [Double]] = [:]
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// `orientation` turned by what faces taught for `backend`.
    mutating func corrected(_ orientation: CGImagePropertyOrientation, backend: BackendKind) -> CGImagePropertyOrientation {
        Self.turned(orientation, quarters: quarters(for: Self.key(backend, orientation)))
    }

    /// Notes the roll Vision measured, in degrees, for a face in a frame of
    /// `backend` whose orientation was `base` before correction. Returns a
    /// line for the trace when the correction changed.
    mutating func note(rollDegrees: Double, backend: BackendKind, base: CGImagePropertyOrientation) -> String? {
        let key = Self.key(backend, base)
        var list = rolls[key, default: []]
        list.append(rollDegrees)
        if list.count > Self.samplesNeeded { list.removeFirst(list.count - Self.samplesNeeded) }
        rolls[key] = list
        guard list.count == Self.samplesNeeded else { return nil }
        let radians = list.map { $0 * .pi / 180 }
        let x = radians.map(cos).reduce(0, +) / Double(list.count)
        let y = radians.map(sin).reduce(0, +) / Double(list.count)
        guard (x * x + y * y).squareRoot() >= Self.minimumAgreement else { return nil }
        let mean = atan2(y, x) * 180 / .pi
        let turn = Self.quarter(of: mean)
        guard turn != 0 else { return nil }
        let updated = (quarters(for: key) + turn) % 4
        turns[key] = updated
        defaults?.set(updated, forKey: Self.defaultsPrefix + key)
        rolls[key] = []
        return "frames of \(backend.rawValue) turned \(turn) more quarter turn\(turn == 1 ? "" : "s") to stand upright: "
            + "faces read a roll of \(Int(mean.rounded())) degrees on average"
    }

    private mutating func quarters(for key: String) -> Int {
        if let known = turns[key] { return known }
        let stored = defaults?.integer(forKey: Self.defaultsPrefix + key) ?? 0
        turns[key] = stored
        return stored
    }

    /// The quarter turn clockwise, 0 to 3, nearest to bringing a face at this
    /// roll upright. Vision's roll grows counterclockwise, so a face at 90
    /// needs a quarter turn clockwise.
    static func quarter(of rollDegrees: Double) -> Int {
        let normalized = (rollDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return Int((normalized / 90).rounded()) % 4
    }

    static func key(_ backend: BackendKind, _ orientation: CGImagePropertyOrientation) -> String {
        "\(backend.rawValue).\(orientation.rawValue)"
    }

    /// An orientation turned by `quarters` more quarter turns clockwise.
    static func turned(_ orientation: CGImagePropertyOrientation, quarters: Int) -> CGImagePropertyOrientation {
        let order: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        guard quarters % 4 != 0, let index = order.firstIndex(of: orientation) else { return orientation }
        return order[(index + quarters % 4 + 4) % 4]
    }
}
