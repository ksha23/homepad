import Foundation
import HomePadCore
import Observation

/// Live sensing details for the diagnostics view. Kept apart from the
/// snapshot so per-frame updates only redraw the diagnostics screen.
@MainActor
@Observable
final class PresenceDiagnostics {
    var mode: SensingMode = .off(.stopped)
    var backend: BackendKind?
    var framesPerSecond: Double = 0
    var rawDistanceMeters: Double?
    var ambientLux: Double?
    var thermalState: ProcessInfo.ThermalState = .nominal
    var lastMotionAt: Date?
    var lastHandGesture: HandGesture?
    var lastError: String?

    func record(_ analysis: FrameAnalysis) {
        backend = analysis.backend
        framesPerSecond = analysis.framesPerSecond
        let observation = analysis.observation
        rawDistanceMeters = observation.nearestPersonMeters
        if let lux = observation.ambientLux { ambientLux = lux }
        if observation.motion { lastMotionAt = observation.timestamp }
        if let gesture = analysis.handGesture { lastHandGesture = gesture }
    }
}

extension ProcessInfo.ThermalState {
    var title: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot (throttled)"
        case .critical: "Critical (camera paused)"
        @unknown default: "Unknown"
        }
    }
}
