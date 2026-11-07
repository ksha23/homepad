import Foundation
import HomePadCore
import Observation

/// Shows the doorbell overlay when `.doorbellRang` arrives, wakes the display,
/// plays the chime, and closes the overlay by itself after the configured time
/// without interaction.
@MainActor
@Observable
final class DoorbellPresenter {
    struct Ring: Equatable, Identifiable {
        let id = UUID()
        let cameraID: HomeCamera.ID
        let rangAt: Date
    }

    private(set) var ring: Ring?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private let chime: DoorbellChime?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    init(settings: SettingsStore, events: EventBus, chime: DoorbellChime? = nil) {
        self.settings = settings
        self.events = events
        self.chime = chime
    }

    /// Starts reacting to doorbell events. Call once after launch.
    func startListening() {
        guard listenTask == nil else { return }
        let stream = events.stream()
        listenTask = Task { [weak self] in
            for await event in stream {
                if case .doorbellRang(let cameraID) = event { self?.present(cameraID: cameraID) }
            }
        }
    }

    func present(cameraID: HomeCamera.ID) {
        ring = Ring(cameraID: cameraID, rangAt: Date())
        events.post(.wake)
        chime?.ring()
        scheduleDismiss()
    }

    /// Any touch on the overlay restarts the auto-dismiss timer.
    func noteInteraction() {
        guard ring != nil else { return }
        scheduleDismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        chime?.stop()
        ring = nil
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let seconds = settings[SmartHomeSettings.doorbell].autoDismissSeconds
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
