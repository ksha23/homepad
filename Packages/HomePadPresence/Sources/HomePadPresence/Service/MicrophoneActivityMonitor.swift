import Foundation
import HomePadCore

/// Presence from microphone activity, used while the cameras are off.
///
/// Reads the shared hub's smoothed level a few times a second. If no other
/// feature keeps the microphone running, it holds a silent subscription so
/// the level stays live.
@MainActor
final class MicrophoneActivityMonitor {
    /// Called with an observation each time activity is heard.
    var onActivity: ((SensorObservation) -> Void)?

    private let services: AppServices
    private var task: Task<Void, Never>?
    private var subscription: UUID?
    private var loudPolls = 0

    init(services: AppServices) {
        self.services = services
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        if !services.microphone.isRunning {
            subscription = services.microphone.subscribe { _, _ in }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let subscription { services.microphone.unsubscribe(subscription) }
        subscription = nil
        loudPolls = 0
    }

    private func poll() {
        let threshold = services.settings[PresenceSettings.sensitivity].voiceActivityLevel
        loudPolls = services.microphone.level >= threshold ? loudPolls + 1 : 0
        // Two loud polls in a row (about a second) filter out single clicks.
        guard loudPolls >= 2 else { return }
        onActivity?(SensorObservation(timestamp: Date(), source: .microphone, voiceActivity: true))
    }
}
