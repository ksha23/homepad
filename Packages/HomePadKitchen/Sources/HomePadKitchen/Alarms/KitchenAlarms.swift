import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// Wake-up alarms: the Alarms app, the ringing alert, the Next Alarm widget
/// and the assistant's alarm tools. They live beside timers, as alarms and
/// timers share the Clock app on iPad, and use the same AlarmKit permission,
/// chimes and background setting.
@MainActor
enum KitchenAlarms {
    static let appID = "alarms"

    /// - Parameter permission: The timers' AlarmKit scheduler, which asks for
    ///   permission once for both.
    @discardableResult
    static func register(services: AppServices, registry: ModuleRegistry, permission: AlarmKitTimerScheduler) -> AlarmService {
        let settings = services.settings
        let rings = AlarmKitAlarmRings(isEnabled: { settings[KitchenSettings.backgroundAlarms] }, permission: permission)
        let household = services.household
        let service = AlarmService(events: services.events, rings: rings, owners: { Set(household.members.map(\.id)) })
        // Before the person changes, or their alarms would be removed as a departed owner's.
        household.onMemberIDChange { [weak service] old, new in service?.moveOwner(from: old, to: new) }
        let chime = ChimePlayer(owner: "kitchen.alarmChime")

        registry.register(app: AppDescriptor(
            id: appID, title: "Alarms", systemImage: "alarm.fill", tint: .orange,
            category: .productivity, sortOrder: 24, requiresRecognizedMember: true
        ) {
            AlarmsAppView().environment(service)
        })
        registry.register(overlay: OverlayDescriptor(id: "kitchen.alarmRinging", zIndex: 81) {
            AlarmRingingOverlay(service: service, chime: chime)
        })
        registry.register(widget: WidgetDescriptor(
            id: "kitchen.nextAlarm", title: "Alarm", systemImage: "alarm.fill",
            supportedSizes: [.small, .medium], isPersonal: true, opensApp: appID
        ) { size in
            NextAlarmWidget(size: size).environment(service)
        })
        registry.register(tools: AlarmTools.make(service: service, household: services.household))

        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { service.refresh() }
        }
        #if DEBUG
        AlarmDebugLaunch.apply(service: service, services: services)
        #endif
        return service
    }
}
