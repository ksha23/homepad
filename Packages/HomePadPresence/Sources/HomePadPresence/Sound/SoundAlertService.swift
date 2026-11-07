@preconcurrency import AVFoundation
import Foundation
import HomePadCore
import Observation

/// Listens for household sounds (smoke alarms, doorbells, crying, breaking
/// glass) through the shared microphone and posts `.soundDetected` events.
/// Smoke and CO alarms also raise a full-screen alert.
@MainActor
@Observable
final class SoundAlertService {
    private(set) var isListening = false
    /// A life-safety alarm waiting to be dismissed.
    private(set) var activeAlarm: SoundAlert?
    /// The latest non-critical alert, shown briefly as a banner.
    private(set) var banner: SoundAlert?
    private(set) var recentAlerts: [SoundAlert] = []
    /// Why listening is off, for the settings pane.
    private(set) var statusMessage: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let classifier = SoundStreamClassifier()
    @ObservationIgnored private var debouncer = SoundEventDebouncer(minimumConfidence: 0.65)
    @ObservationIgnored private var subscription: UUID?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
        classifier.onDetection = { [weak self] kind, confidence in
            Task { @MainActor in self?.handle(kind: kind, confidence: confidence, at: Date()) }
        }
    }

    /// Starts or stops listening to match settings and permission.
    func update() {
        let settings = services.settings
        debouncer.minimumConfidence = settings[PresenceSettings.soundSensitivity].soundConfidence
        debouncer.enabledKinds = Set(settings[PresenceSettings.alertSounds].compactMap(SoundAlertKind.init(rawValue:)))

        if !settings[CoreSettings.soundAlertsEnabled] {
            stopListening(reason: "Sound alerts are off.")
        } else if !settings[CoreSettings.microphoneEnabled] {
            stopListening(reason: "The microphone is turned off.")
        } else if MicrophonePermission.status != .granted {
            stopListening(reason: MicrophonePermission.status == .denied
                ? "Microphone access is off in Settings." : "Allow microphone access to hear alarms.")
        } else {
            startListening()
        }
    }

    func dismissAlarm() {
        activeAlarm = nil
    }

    /// Feeds a fake detection through the same debounce path (simulator and the
    /// settings "Test" button). Enough hits are sent to pass confirmation.
    func simulate(_ kind: SoundAlertKind) {
        var probe = debouncer
        probe.enabledKinds.insert(kind)
        probe.reset()
        for _ in 0..<kind.requiredHits {
            if let alert = probe.process(kind: kind, confidence: 0.9, at: Date()) { deliver(alert) }
        }
    }

    // MARK: Private

    private func startListening() {
        statusMessage = nil
        guard subscription == nil else { return }
        let classifier = self.classifier
        subscription = services.microphone.subscribe { buffer, time in classifier.append(buffer, at: time) }
        isListening = true
    }

    private func stopListening(reason: String) {
        statusMessage = reason
        if let subscription { services.microphone.unsubscribe(subscription) }
        subscription = nil
        if isListening { classifier.reset() }
        isListening = false
    }

    private func handle(kind: SoundAlertKind, confidence: Double, at time: Date) {
        guard isListening, let alert = debouncer.process(kind: kind, confidence: confidence, at: time) else { return }
        deliver(alert)
    }

    private func deliver(_ alert: SoundAlert) {
        services.events.post(.soundDetected(label: alert.kind.eventLabel, confidence: alert.confidence))
        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > 10 { recentAlerts.removeLast(recentAlerts.count - 10) }
        if alert.kind.isCritical {
            activeAlarm = alert
            services.events.post(.wake)
        } else {
            showBanner(alert)
        }
    }

    private func showBanner(_ alert: SoundAlert) {
        banner = alert
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
