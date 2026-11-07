import Foundation
import HomePadCore

/// A scripted visitor for the simulator: someone walks up to the iPad,
/// looks at it, and leaves, so the shell and faces can be screenshot-tested.
struct SimulatedPresenceScript: Sendable {
    enum Mode: Equatable, Sendable {
        case cycle
        case hold(ProximityLevel)

        init?(argument: String) {
            switch argument.lowercased() {
            case "cycle": self = .cycle
            case "nobody": self = .hold(.nobody)
            case "far": self = .hold(.far)
            case "mid": self = .hold(.mid)
            case "near": self = .hold(.near)
            default: return nil
            }
        }
    }

    /// One leg of the visit.
    struct Phase: Sendable {
        var duration: TimeInterval
        /// Nil means nobody is there.
        var distance: Double?
        var people = 1
        var looking = false
    }

    var mode: Mode

    /// Nobody, far, mid, near (looking), mid, far. Eight seconds each.
    static let visit: [Phase] = [
        Phase(duration: 8, distance: nil, people: 0),
        Phase(duration: 8, distance: 3.2),
        Phase(duration: 8, distance: 1.8, people: 2, looking: true),
        Phase(duration: 8, distance: 0.6, looking: true),
        Phase(duration: 8, distance: 1.6, looking: true),
        Phase(duration: 8, distance: 3.0),
    ]

    /// The phase at `elapsed` seconds since the script started.
    func phase(at elapsed: TimeInterval) -> Phase {
        switch mode {
        case .hold(let level):
            return Self.phase(for: level)
        case .cycle:
            let total = Self.visit.reduce(0) { $0 + $1.duration }
            var time = elapsed.truncatingRemainder(dividingBy: total)
            for phase in Self.visit {
                if time < phase.duration { return phase }
                time -= phase.duration
            }
            return Self.visit[0]
        }
    }

    /// An observation for `elapsed` seconds, with a little distance jitter.
    func observation(at elapsed: TimeInterval, now: Date) -> SensorObservation {
        let phase = phase(at: elapsed)
        var observation = SensorObservation(timestamp: now, source: .trueDepth, ambientLux: 180)
        // Stands in for ARKit face tracking.
        observation.facesAreTracked = true
        guard let distance = phase.distance else { return observation }
        let jitter = sin(elapsed * 1.7) * 0.05
        observation.faces = (0..<phase.people).map { index in
            DetectedFace(distanceMeters: distance + jitter + Double(index) * 0.6, isLookingAtScreen: phase.looking && index == 0)
        }
        observation.motion = Int(elapsed) % 4 == 0
        return observation
    }

    private static func phase(for level: ProximityLevel) -> Phase {
        switch level {
        case .nobody: Phase(duration: .infinity, distance: nil, people: 0)
        case .far: Phase(duration: .infinity, distance: 3.2)
        case .mid: Phase(duration: .infinity, distance: 1.7, looking: true)
        case .near: Phase(duration: .infinity, distance: 0.6, looking: true)
        }
    }
}
