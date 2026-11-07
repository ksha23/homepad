import Foundation
import HomePadCore

/// A trace of sensing and recognition for finding slow recognition on a device.
/// Launching with `-HomePadPresenceTrace YES` writes Documents/presence-trace.txt.
@MainActor
enum PresenceTrace {
    static let trace = DebugTrace(file: "presence-trace.txt", argument: "HomePadPresenceTrace")

    static func describe(_ decision: MatchDecision, names: [UUID: String]) -> String {
        switch decision {
        case .member(let id, let score): "match \(names[id] ?? "?") \(format(score))"
        case .unknown(let best): "unknown best \(format(best))"
        case .spoof: "spoof"
        }
    }

    static func describe(_ liveness: LivenessResult?) -> String {
        guard let liveness else { return "no depth" }
        let distance = liveness.distanceMeters.map { " at \(format($0))m" } ?? ""
        let verdict = liveness.unsure.map { "unsure (\($0.description))" } ?? (liveness.isLive ? "live" : "flat")
        return "\(verdict) relief \(format(liveness.reliefMeters * 1000))mm valid \(format(liveness.validFraction)) "
            + "face \(format(liveness.faceFraction))" + distance
    }

    /// " pose yaw 12 pitch -4" in degrees from Vision's head pose, or nothing.
    static func describePose(_ sample: FaceEmbeddingSample) -> String {
        guard let yaw = sample.yaw, let pitch = sample.pitch else { return "" }
        return " pose yaw \(Int((yaw * 180 / .pi).rounded())) pitch \(Int((pitch * 180 / .pi).rounded()))"
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
