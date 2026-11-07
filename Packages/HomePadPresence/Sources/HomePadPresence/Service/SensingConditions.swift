import Foundation
import HomePadCore
import UIKit

/// Watches app state and thermal state, and works out whether the camera and
/// microphone may be used. Calls `onChange` whenever something relevant moves.
@MainActor
final class SensingConditions {
    private(set) var isAppActive: Bool
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    var onChange: (() -> Void)?
    /// Called when files protected with complete protection become readable.
    var onProtectedDataAvailable: (() -> Void)?

    /// The capture-claim owner Presence itself uses (never blocks itself).
    static let captureOwner = "presence.sensor"
    /// Grace period before a resign-active pauses the camera, so pulling down
    /// Control Center for a moment does not restart the sensors.
    private let inactiveGrace: Duration = .seconds(3)
    private var observers: [NSObjectProtocol] = []
    private var resignTask: Task<Void, Never>?

    init() {
        isAppActive = UIApplication.shared.applicationState == .active
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                // Always report, since permissions may have changed behind a system prompt.
                MainActor.assumeIsolated {
                    self?.setActive(true)
                    self?.onChange?()
                }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleInactive() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setActive(false) }
            },
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onProtectedDataAvailable?() }
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.thermalState = ProcessInfo.processInfo.thermalState
                    self?.onChange?()
                }
            },
        ]
    }

    /// Whether the camera may run, and if not, the most useful reason.
    func cameraAvailability(services: AppServices, capabilities: SensingCapabilities) -> CameraAvailability {
        if !services.settings[CoreSettings.cameraEnabled] { return .unavailable(.cameraSettingOff) }
        if let claim = services.capture.foregroundClaim, claim.owner != Self.captureOwner {
            return .unavailable(.cameraInUse)
        }
        if !services.capture.camerasAllowed { return .unavailable(.camerasDisabled) }
        if capabilities.isSimulated { return .available }
        if !capabilities.hasFrontCamera && !capabilities.hasTrueDepth { return .unavailable(.noCamera) }
        switch CameraPermission.status {
        case .granted: return .available
        case .undetermined: return .unavailable(.permissionNeeded)
        case .denied: return .unavailable(.permissionDenied)
        }
    }

    /// Whether microphone activity can stand in for the camera.
    func isMicrophoneAvailable(services: AppServices) -> Bool {
        services.settings[CoreSettings.microphoneEnabled] && MicrophonePermission.status == .granted
    }

    private func scheduleInactive() {
        resignTask?.cancel()
        resignTask = Task { [weak self, inactiveGrace] in
            try? await Task.sleep(for: inactiveGrace)
            guard !Task.isCancelled else { return }
            self?.setActive(false)
        }
    }

    private func setActive(_ active: Bool) {
        resignTask?.cancel()
        resignTask = nil
        guard active != isAppActive else { return }
        isAppActive = active
        onChange?()
    }
}
