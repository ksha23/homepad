import HomePadCore
import HomePadUI
import SwiftUI

/// TrueDepth and camera presence, recognition, gestures, sounds and the Mirror app.
public enum PresenceModule: HomePadModule {
    public static let id = "presence"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let presence = LivePresenceService(services: services)
        services.presence = presence
        // Before the person changes, or their templates would be deleted as a removed person's.
        services.household.onMemberIDChange { [weak presence] old, new in
            presence?.recognition.moveMember(from: old, to: new)
        }

        registry.register(app: AppDescriptor(
            id: "mirror", title: "Mirror", systemImage: "person.crop.rectangle", tint: .gray,
            category: .camera, sortOrder: 60
        ) {
            MirrorAppView()
        })
        registry.register(settings: SettingsPaneDescriptor(
            id: "presence", title: "Presence & Privacy", systemImage: "person.wave.2.fill", tint: .teal, sortOrder: 30
        ) {
            PresenceSettingsPane(presence: presence)
        })
        registry.register(overlay: OverlayDescriptor(id: "presence.soundAlerts", zIndex: 900) {
            SoundAlertOverlay(sounds: presence.sounds)
        })
        registry.register(tool: PresenceTools.status(presence: presence, household: services.household))
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        services.presence.start()
        applySimulatorOptions(services: services)
    }

    /// Simulator conveniences from `PresenceLaunchOptions`.
    private static func applySimulatorOptions(services: AppServices) {
        let options = PresenceLaunchOptions.current
        guard options.isSimulated || options.simulatedSound != nil,
              let presence = services.presence as? LivePresenceService else { return }
        // Enrollment screenshots need someone to enroll.
        if options.debugPane == .enroll, services.household.members.isEmpty {
            services.household.add(HouseholdMember(name: "Kyle", avatar: "K", colorHex: "#0A84FF", isAdmin: true))
        }
        if let kind = options.simulatedSound {
            Task {
                try? await Task.sleep(for: .seconds(3))
                presence.sounds.simulate(kind)
            }
        }
    }
}
