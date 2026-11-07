@preconcurrency import CoreMotion
import Foundation
import HomePadCore
import Observation

/// AirPods head gestures: nod for yes, shake for no.
///
/// Connection status is watched all the time (cheap). Motion updates run only
/// while listening, which happens when another module asks through
/// `HomePadEvent.listenForHeadGestures(seconds:)` or while the assistant is
/// speaking, the moment a yes or no question is likely.
@MainActor
@Observable
final class HeadGestureService {
    private(set) var isHeadphonesConnected = false
    private(set) var isListening = false
    private(set) var lastGesture: HeadGesture?
    /// Why head gestures cannot run, if they cannot.
    private(set) var unavailableReason: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var manager: CMHeadphoneMotionManager?
    @ObservationIgnored private let connection = ConnectionDelegate()
    @ObservationIgnored private var detector = HeadGestureDetector()
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
        connection.onChange = { [weak self] connected in
            Task { @MainActor in self?.connectionChanged(connected) }
        }
    }

    /// Head tracking needs `NSMotionUsageDescription` in Info.plist. Without it
    /// iOS terminates the app on first use, so the feature stays off instead.
    static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") != nil
    }

    /// Starts or stops connection monitoring to match the setting.
    func update() {
        guard services.settings[PresenceSettings.headGestures] else {
            unavailableReason = nil
            shutDown()
            return
        }
        guard Self.hasUsageDescription else {
            unavailableReason = "Needs a motion usage description in the app's Info.plist."
            shutDown()
            return
        }
        unavailableReason = nil
        guard manager == nil else { return }
        let manager = CMHeadphoneMotionManager()
        manager.delegate = connection
        manager.startConnectionStatusUpdates()
        self.manager = manager
        isHeadphonesConnected = manager.isConnectionStatusActive
    }

    /// Listens for a nod or shake for `seconds`. No-op without headphones.
    func listen(for seconds: TimeInterval) {
        guard let manager, isHeadphonesConnected, manager.isDeviceMotionAvailable else { return }
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stopListening()
        }
        guard !isListening else { return }
        detector.reset()
        isListening = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let sample = HeadMotionSample(time: motion.timestamp, pitch: motion.attitude.pitch, yaw: motion.attitude.yaw)
            MainActor.assumeIsolated { self?.process(sample) }
        }
    }

    func stopListening() {
        stopTask?.cancel()
        stopTask = nil
        guard isListening else { return }
        manager?.stopDeviceMotionUpdates()
        isListening = false
    }

    private func process(_ sample: HeadMotionSample) {
        guard let gesture = detector.add(sample) else { return }
        lastGesture = gesture
        services.events.post(.headGesture(gesture))
    }

    private func connectionChanged(_ connected: Bool) {
        isHeadphonesConnected = connected
        if !connected { stopListening() }
    }

    private func shutDown() {
        stopListening()
        manager?.stopConnectionStatusUpdates()
        manager = nil
        isHeadphonesConnected = false
    }
}

/// Forwards headphone connect and disconnect callbacks.
private final class ConnectionDelegate: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    var onChange: ((Bool) -> Void)?

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { onChange?(true) }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) { onChange?(false) }
}
