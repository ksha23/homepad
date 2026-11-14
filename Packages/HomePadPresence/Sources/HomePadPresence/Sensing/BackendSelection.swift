import Foundation
import HomePadCore

/// The sensing paths HomePad can run.
enum BackendKind: String, Sendable {
    /// Every kind except the simulator opens a real camera.
    var usesCamera: Bool { self != .simulated }

    /// ARKit face tracking on the TrueDepth (infrared) camera. Distance, gaze and
    /// up to three faces, in the dark too. Used while someone is present.
    case faceTracking
    /// AVCapture on the TrueDepth camera with the depth stream at a low frame rate.
    /// Sees bodies without faces and works in the dark. Used to scan dark rooms.
    case depthScan
    /// AVCapture on the RGB front camera with Vision. Fallback path, and the
    /// cheapest scan on a TrueDepth iPad when the room is lit.
    case frontCamera
    /// Scripted readings for the simulator (`-HomePadSimulatePresence`).
    case simulated

    var title: String {
        switch self {
        case .faceTracking: "TrueDepth face tracking"
        case .depthScan: "TrueDepth depth scan"
        case .frontCamera: "Front camera"
        case .simulated: "Simulated"
        }
    }
}

/// What this iPad can do.
struct SensingCapabilities: Equatable, Sendable {
    var hasTrueDepth: Bool
    var hasFrontCamera: Bool
    var isSimulated: Bool
}

/// Picks the backend for a duty-cycle mode. Pure, so the efficiency rules are testable.
///
/// On a TrueDepth iPad, ARKit face tracking is the richest path but runs the
/// camera and face mesh at 30 to 60 fps, which is too costly around the clock.
/// It therefore only runs while someone is present. With nobody around the
/// scan uses AVCapture at about 2 fps: the plain RGB stream when the room is
/// lit, and the TrueDepth session with its depth stream when it is dark,
/// since depth sees movement without light.
///
/// Face tracking runs while someone is present in any light: its face mesh
/// comes from the dot projector, which needs no light, and recognition in the
/// dark is to come from it (README, "Depth identity").
///
/// The depth scan cannot measure the light, so a reading counts for three
/// minutes (`LivePresenceService.selectionLight`), and nil light starts a
/// backend that measures it.
enum BackendSelector {
    /// The depth scan's rate.
    static let depthScanFramesPerSecond = 2.0

    static func kind(
        for mode: SensingMode, capabilities: SensingCapabilities,
        preferTrueDepth: Bool, ambientLight: AmbientLight?
    ) -> BackendKind? {
        guard mode.usesCamera else { return nil }
        if capabilities.isSimulated { return .simulated }
        let trueDepth = capabilities.hasTrueDepth && preferTrueDepth
        switch mode {
        case .active:
            if trueDepth { return .faceTracking }
            return capabilities.hasFrontCamera ? .frontCamera : nil
        case .scanning:
            if trueDepth && isDark(ambientLight) { return .depthScan }
            return capabilities.hasFrontCamera || trueDepth ? .frontCamera : nil
        case .off, .microphoneOnly:
            return nil
        }
    }

    /// Frame rate for `kind` in a mode that asks for `framesPerSecond`.
    static func framesPerSecond(for kind: BackendKind, mode framesPerSecond: Double) -> Double {
        kind == .depthScan ? min(framesPerSecond, depthScanFramesPerSecond) : framesPerSecond
    }

    /// Unknown light is not dark: the front camera has to measure it first.
    private static func isDark(_ light: AmbientLight?) -> Bool {
        switch light {
        case .dark, .dim: true
        case .none, .normal, .bright: false
        }
    }
}
