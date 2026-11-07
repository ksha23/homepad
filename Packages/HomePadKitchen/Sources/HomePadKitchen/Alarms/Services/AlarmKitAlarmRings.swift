import AlarmKit
import Foundation
import HomePadCore
import SwiftUI

/// Rings wake-up alarms with AlarmKit while HomePad is in the background or
/// the iPad is locked, with a Snooze button where the alarm allows it.
///
/// Each alarm has one system alarm, set for its next ring one second late. In
/// the foreground the alarm service rings first, cancels it, and sets the
/// next one. Permission is the one timers ask for, through
/// `AlarmKitTimerScheduler`, so Settings > Kitchen shows a single state, and
/// the Kitchen setting for background alarms covers both.
@MainActor
final class AlarmKitAlarmRings: AlarmRingScheduling {
    /// Seconds between the in-app ring and the system alarm.
    static let foregroundGrace: TimeInterval = 1

    private let isEnabled: () -> Bool
    private let permission: any TimerAlarmScheduling
    private let defaults: UserDefaults
    private var queue: Task<Void, Never>?
    private let log = Log.make("Kitchen.WakeAlarms")
    private static let scheduledKey = "kitchen.alarmKit.wakeAlarmIDs"

    /// - Parameters:
    ///   - isEnabled: Reads the Kitchen setting at call time.
    ///   - permission: Asks for AlarmKit permission and knows the answer.
    init(isEnabled: @escaping () -> Bool, permission: any TimerAlarmScheduling, defaults: UserDefaults = .standard) {
        self.isEnabled = isEnabled
        self.permission = permission
        self.defaults = defaults
    }

    /// Alarms that have a system alarm, persisted so a relaunch still knows.
    private var scheduledIDs: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.scheduledKey) ?? []).compactMap(UUID.init)) }
        set { defaults.set(newValue.map(\.uuidString), forKey: Self.scheduledKey) }
    }

    func schedule(_ alarm: HomeAlarm, at date: Date) {
        guard isEnabled() else { return }
        let id = alarm.id
        let configuration = Self.configuration(for: alarm, at: date.addingTimeInterval(Self.foregroundGrace))
        enqueue { [weak self] in
            guard let self else { return }
            if self.permission.authorization == .notDetermined { await self.permission.requestAuthorization() }
            guard self.permission.authorization == .authorized else { return }
            try? AlarmManager.shared.cancel(id: id)
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                self.scheduledIDs.insert(id)
            } catch {
                self.log.error("Scheduling a wake-up alarm failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancel(_ id: UUID) {
        enqueue { [weak self] in
            guard let self, self.permission.authorization == .authorized else { return }
            try? AlarmManager.shared.cancel(id: id)
            self.scheduledIDs.remove(id)
        }
    }

    func wasDismissedOutsideApp(_ id: UUID) -> Bool {
        guard scheduledIDs.contains(id), let alarms = try? AlarmManager.shared.alarms else { return false }
        if alarms.contains(where: { $0.id == id }) { return false }
        scheduledIDs.remove(id)
        return true
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// A fixed alarm with the label as its title. With snooze allowed, its
    /// Snooze button counts down nine minutes and rings again.
    private static func configuration(for alarm: HomeAlarm, at date: Date) -> AlarmManager.AlarmConfiguration<KitchenAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: alarm.title)
        let snooze = alarm.allowsSnooze
            ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz") : nil
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: snooze, secondaryButtonBehavior: snooze.map { _ in .countdown })
        } else {
            alert = AlarmPresentation.Alert(
                title: title, stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: snooze, secondaryButtonBehavior: snooze.map { _ in .countdown })
        }
        let countdown = alarm.allowsSnooze ? Alarm.CountdownDuration(preAlert: nil, postAlert: HomeAlarm.snoozeLength) : nil
        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdown, schedule: .fixed(date),
            attributes: AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: KitchenAlarmMetadata(), tintColor: .orange),
            stopIntent: nil, secondaryIntent: nil, sound: .default)
    }
}
