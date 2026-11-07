#if DEBUG
import Foundation
import HomePadCore

/// Launch arguments that put alarms into a known state for simulator
/// screenshots. Debug builds only. They need a member, so pair them with
/// `-HomePadDemoContent YES -HomePadMember Alex -HomePadRecognized YES`.
///
///     -KitchenDemo alarms             three alarms for the member at the screen
///     -KitchenDemo alarmRinging       those, with the first ringing
///     -KitchenDemoAlarmEditor new     the New Alarm sheet over Alarms
///     -KitchenDemoAlarmEditor edit    the first alarm in the editor
@MainActor
enum AlarmDebugLaunch {
    static func apply(service: AlarmService, services: AppServices) {
        let mode = UserDefaults.standard.string(forKey: "KitchenDemo")
        guard mode == "alarms" || mode == "alarmRinging" else { return }
        let household = services.household
        // The shell picks the demo member after the modules register.
        Task { @MainActor in
            for _ in 0..<50 where household.activeMember == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let owner = household.activeMember?.id else { return }
            for alarm in service.alarms(ownedBy: owner) { service.delete(alarm.id) }
            let wake = service.add(HomeAlarm(ownerID: owner, hour: 6, minute: 30, label: "Wake Up", weekdays: Locale.Weekday.workweek))
            service.add(HomeAlarm(ownerID: owner, hour: 8, minute: 15, label: "", weekdays: Locale.Weekday.weekend))
            service.add(HomeAlarm(ownerID: owner, hour: 21, minute: 45, label: "Pills", isEnabled: false))
            if mode == "alarmRinging" { service.ringNow(wake.id) }
        }
    }

    /// The editor to open over Alarms, from `-KitchenDemoAlarmEditor`.
    static func editorDraft(service: AlarmService, owner: UUID?) -> AlarmDraft? {
        guard let owner, let mode = UserDefaults.standard.string(forKey: "KitchenDemoAlarmEditor") else { return nil }
        if mode == "edit", let first = service.alarms(ownedBy: owner).first { return AlarmDraft(alarm: first, isNew: false) }
        return AlarmDraft(alarm: HomeAlarm(ownerID: owner, hour: 7, minute: 0), isNew: true)
    }
}

#endif
