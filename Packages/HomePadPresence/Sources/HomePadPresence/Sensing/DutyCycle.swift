import Foundation

/// Why camera sensing is paused or replaced by the microphone.
public enum SensingPauseReason: String, Sendable {
    case stopped
    case appInactive
    case cameraSettingOff
    case cameraInUse
    case camerasDisabled
    case permissionNeeded
    case permissionDenied
    case noCamera
    case thermal

    /// Plain description for diagnostics.
    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .appInactive: "App not active"
        case .cameraSettingOff: "Camera turned off"
        case .cameraInUse: "Camera in use by another feature"
        case .camerasDisabled: "Cameras disabled"
        case .permissionNeeded: "Camera permission not asked yet"
        case .permissionDenied: "Camera permission denied"
        case .noCamera: "No camera available"
        case .thermal: "iPad is too warm"
        }
    }
}

/// What the presence sensors should be doing right now.
public enum SensingMode: Equatable, Sendable {
    /// Nothing runs.
    case off(SensingPauseReason)
    /// Cameras are unavailable, so presence comes from microphone activity.
    case microphoneOnly(SensingPauseReason)
    /// Nobody around: a cheap low-rate scan.
    case scanning(framesPerSecond: Double)
    /// Someone is present: full-rate tracking.
    case active(framesPerSecond: Double)

    var usesCamera: Bool {
        switch self {
        case .scanning, .active: true
        case .off, .microphoneOnly: false
        }
    }

    var framesPerSecond: Double? {
        switch self {
        case .scanning(let fps), .active(let fps): fps
        case .off, .microphoneOnly: nil
        }
    }

    var title: String {
        switch self {
        case .off(let reason): "Off (\(reason.title))"
        case .microphoneOnly(let reason): "Microphone only (\(reason.title))"
        case .scanning(let fps): "Scanning at \(Self.format(fps)) fps"
        case .active(let fps): "Active at \(Self.format(fps)) fps"
        }
    }

    private static func format(_ fps: Double) -> String {
        fps >= 1 ? String(Int(fps.rounded())) : String(format: "%.1f", fps)
    }
}

/// Whether the camera may be used, and if not, why.
enum CameraAvailability: Equatable, Sendable {
    case available
    case unavailable(SensingPauseReason)
}

/// Everything the duty cycle depends on. Gathered by the service from settings,
/// the capture arbiter, app state, permissions and thermal state.
struct DutyCycleInputs: Equatable, Sendable {
    var isStarted = true
    var isAppActive = true
    var camera: CameraAvailability = .available
    var isMicrophoneAvailable = false
    var thermalState: ProcessInfo.ThermalState = .nominal
    /// Last time anyone was detected by a camera.
    var lastPresenceAt: Date?
}

/// Rates and timings for the duty cycle.
struct DutyCycleConfig: Equatable, Sendable {
    var activeFPS: Double = 10
    var scanFPS: Double = 2
    /// Seconds with nobody detected before full rate drops back to scanning.
    var cooldown: TimeInterval = 20

    /// Rates after thermal throttling. Nil means the camera must stop.
    func rates(for thermal: ProcessInfo.ThermalState) -> (active: Double, scan: Double)? {
        switch thermal {
        case .nominal: (activeFPS, scanFPS)
        case .fair: (activeFPS * 3 / 5, scanFPS)
        case .serious: (activeFPS * 3 / 10, scanFPS / 2)
        case .critical: nil
        @unknown default: (activeFPS * 3 / 10, scanFPS / 2)
        }
    }
}

/// The 24/7 duty-cycle state machine. Pure: the same inputs and time always
/// give the same mode, which keeps it easy to test.
///
/// - Paused when stopped or the app is inactive.
/// - Microphone only when the camera is unavailable or the iPad is critically hot.
/// - Active at full rate while someone was seen within `cooldown`, scanning otherwise.
/// - Rates shrink as `ProcessInfo.thermalState` rises.
struct DutyCyclePolicy: Sendable {
    var config = DutyCycleConfig()

    func mode(for inputs: DutyCycleInputs, now: Date) -> SensingMode {
        guard inputs.isStarted else { return .off(.stopped) }
        guard inputs.isAppActive else { return .off(.appInactive) }
        if case .unavailable(let reason) = inputs.camera {
            return fallback(reason, microphone: inputs.isMicrophoneAvailable)
        }
        guard let rates = config.rates(for: inputs.thermalState) else {
            return fallback(.thermal, microphone: inputs.isMicrophoneAvailable)
        }
        if isRecentlyPresent(inputs.lastPresenceAt, now: now) {
            return .active(framesPerSecond: rates.active)
        }
        return .scanning(framesPerSecond: rates.scan)
    }

    /// When the mode will change on its own (active cooling down to scanning),
    /// so the service can schedule one re-evaluation instead of polling.
    func nextTransition(for inputs: DutyCycleInputs, now: Date) -> Date? {
        guard case .active = mode(for: inputs, now: now), let last = inputs.lastPresenceAt else { return nil }
        return last.addingTimeInterval(config.cooldown)
    }

    private func isRecentlyPresent(_ last: Date?, now: Date) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) < config.cooldown
    }

    private func fallback(_ reason: SensingPauseReason, microphone: Bool) -> SensingMode {
        microphone ? .microphoneOnly(reason) : .off(reason)
    }
}
