import ActivityKit
import AlarmKit
import Foundation
import HomePadCore
import Observation
import SwiftUI

/// Empty metadata. AlarmKit requires a type even when there is nothing to carry.
struct KitchenAlarmMetadata: AlarmMetadata {}

/// Rings kitchen timers with AlarmKit so they sound even when HomePad is in the
/// background or the iPad is locked.
///
/// Each running timer gets a fixed-date alarm one second after it ends. In the
/// foreground the service notices the end first and cancels the alarm, so only
/// the in-app overlay rings. The countdown itself is shown by HomePad's own Live
/// Activity, so these alarms carry no countdown presentation.
///
/// Authorization is requested the first time a timer starts. AlarmKit calls are
/// serialized so a quick pause right after a start cannot leave a stray alarm.
@MainActor
@Observable
public final class AlarmKitTimerScheduler: TimerAlarmScheduling {
    public private(set) var authorization: TimerAlarmAuthorization = .notDetermined

    /// Seconds between a timer's end and its system alarm.
    static let foregroundGrace: TimeInterval = 1

    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var queue: Task<Void, Never>?
    private let log = Log.make("Kitchen.Alarms")
    private static let scheduledKey = "kitchen.alarmKit.scheduledIDs"

    /// - Parameter isEnabled: Reads the Kitchen setting at call time.
    public init(isEnabled: @escaping () -> Bool, defaults: UserDefaults = .standard) {
        self.isEnabled = isEnabled
        self.defaults = defaults
        refreshAuthorization()
    }

    /// Timers that have a system alarm, persisted so a relaunch still knows.
    private var scheduledIDs: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.scheduledKey) ?? []).compactMap(UUID.init)) }
        set { defaults.set(newValue.map(\.uuidString), forKey: Self.scheduledKey) }
    }

    public func requestAuthorization() async {
        do {
            authorization = Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            log.error("AlarmKit authorization failed: \(error.localizedDescription, privacy: .public)")
            authorization = .unavailable
        }
    }

    public func schedule(_ timer: HomeTimer) {
        guard isEnabled(), let end = timer.endDate else { return }
        let id = timer.id
        let label = timer.label
        enqueue { [weak self] in
            guard let self else { return }
            if self.authorization == .notDetermined { await self.requestAuthorization() }
            guard self.authorization == .authorized else { return }
            try? AlarmManager.shared.cancel(id: id)
            do {
                let configuration = AlarmManager.AlarmConfiguration<KitchenAlarmMetadata>(
                    schedule: .fixed(end.addingTimeInterval(Self.foregroundGrace)),
                    attributes: Self.attributes(label: label),
                    stopIntent: nil, secondaryIntent: nil, sound: .default)
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                self.scheduledIDs.insert(id)
            } catch {
                self.log.error("Scheduling alarm failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Queued behind any pending schedule call for the same timer. Touches
    /// AlarmKit only once alarms are allowed, so finishing a timer never asks.
    public func cancel(_ id: UUID) {
        enqueue { [weak self] in
            guard let self, self.authorization == .authorized else { return }
            try? AlarmManager.shared.cancel(id: id)
            self.scheduledIDs.remove(id)
        }
    }

    public func wasDismissedOutsideApp(_ id: UUID) -> Bool {
        guard scheduledIDs.contains(id), let alarms = try? AlarmManager.shared.alarms else { return false }
        if alarms.contains(where: { $0.id == id }) { return false }
        scheduledIDs.remove(id)
        return true
    }

    // MARK: Helpers

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func refreshAuthorization() {
        authorization = Self.map(AlarmManager.shared.authorizationState)
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> TimerAlarmAuthorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    private static func attributes(label: String) -> AlarmAttributes<KitchenAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: label)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title, stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"))
        }
        return AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: KitchenAlarmMetadata(), tintColor: .orange)
    }
}
