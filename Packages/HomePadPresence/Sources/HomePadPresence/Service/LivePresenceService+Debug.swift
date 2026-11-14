import Foundation
import HomePadCore

/// What the recognition debug view shows: the camera's and the depth sensor's
/// view of the last frame, and lines saying what recognition made of them.
struct RecognitionDebugState {
    var frame: RecognitionDebugFrame
    var lines: [String]
}

extension LivePresenceService {
    /// One line per stage, from the sensors to the session.
    func debugLines(_ analysis: FrameAnalysis, frame: RecognitionDebugFrame) -> [String] {
        let observation = analysis.observation
        let light = snapshot.ambientLight.map { "\($0)" } ?? "unknown"
        let lux = snapshot.ambientLux.map { " (\(Int($0.rounded())) lux)" } ?? ""
        var lines = ["\(analysis.backend.title) at \(Int(analysis.framesPerSecond.rounded())) fps, light \(light)\(lux)"]

        let faces = observation.faces.count
        if faces == 0 {
            lines.append("Camera: no face")
        } else {
            let by = observation.facesAreTracked ? "tracked by ARKit" : "found by Vision"
            lines.append("Camera: \(faces) face\(faces == 1 ? "" : "s"), \(by)")
        }
        lines.append("Depth map: " + frame.depthSource)
        lines.append(observation.depthPersonMeters.map { String(format: "Depth: person at %.2f m", $0) } ?? "Depth: no person followed")
        lines.append("Depth face: " + frame.depthFace)
        lines.append("Camera recognition: " + (recognition.lastSampleSummary ?? "no sample yet"))
        lines.append("Depth identity: " + (recognition.depthIdentity.lastSummary ?? "no signature yet"))
        lines.append("Session: " + sessionDescription)
        return lines
    }

    private var sessionDescription: String {
        let household = services.household
        let name = { (id: UUID) in household.members.first { $0.id == id }?.name ?? "someone" }
        switch household.session.mode {
        case .guest: return "guest"
        case .picked(let id): return "\(name(id)), picked by hand"
        case .recognized(let id): return "\(name(id)), recognized"
        case .verified(let id): return "\(name(id)), verified"
        }
    }
}
