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
/// In a dim or dark room the depth scan also runs while someone is present,
/// slowly. ARKit's camera runs at 30 fps, so each frame gets at most 1/30 s
/// of light: it found a face in about half its frames at 20 lux and more, and
/// in none at 1 to 3 lux. At 2 fps each frame can take up to half a second,
/// and on those frames Vision found a face at 1.7 m in a 1 lux room. The
/// front camera reads a room far brighter than ARKit does (15 lux against 1
/// in the same dark room), so dim by its reading is already too dark for
/// ARKit. Keeping the scan's backend also keeps the person: switching to face
/// tracking and back left 4 s with no camera, long enough for presence to end.
///
/// The depth scan cannot measure the light, so a reading counts for three
/// minutes (`LivePresenceService.selectionLight`), and nil light starts a
/// backend that measures it.
enum BackendSelector {
    /// The depth scan's rate, also while someone is present (see above).
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
            if trueDepth { return isDark(ambientLight) ? .depthScan : .faceTracking }
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
