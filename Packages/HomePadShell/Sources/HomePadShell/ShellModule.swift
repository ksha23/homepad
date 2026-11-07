import HomePadCore
import HomePadUI
import SwiftUI

/// The shell owns navigation (face, Home Screen, apps), the kiosk / always-on
/// controller and system surfaces: Control Center, the People switcher, the
/// recognition gate, the Settings app and onboarding.
///
/// It registers the Settings app, the built-in clock face, the Glance and Home
/// Status widgets, the glance as a mini widget, and the Kiosk & Display,
/// People, Background Tasks and About settings panes. On the iPad it hosts
/// background work (`BackgroundWorkHost`).
/// The app target shows `ShellRootView`.
public enum ShellModule: HomePadModule {
    public static let id = "shell"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        registry.register(app: AppDescriptor(
            id: KnownAppID.settings, title: "Settings", systemImage: "gearshape.fill", tint: .gray,
            category: .system, sortOrder: 900
        ) {
            SettingsAppView()
        })
        registry.register(face: FaceDescriptor(
            id: FaceResolver.builtInClockID, title: "Clock", systemImage: "clock", sortOrder: 900
        ) {
            BuiltInClockFace()
        })
        GlanceWidgets.register(in: registry)
        GlanceMiniWidget.register(in: registry)
        HomeScreenSharing.register(services: services, in: registry)
        registry.register(settings: SettingsPaneDescriptor(
            id: ShellPaneID.people, title: "People", systemImage: "person.2.fill", tint: .blue, sortOrder: 5
        ) {
            PeopleSettingsPane()
        })
        registry.register(settings: SettingsPaneDescriptor(
            id: ShellPaneID.kiosk, title: "Kiosk & Display", systemImage: "ipad.landscape", sortOrder: 10, adminOnly: true
        ) {
            KioskSettingsPane()
        })
        registry.register(settings: SettingsPaneDescriptor(
            id: ShellPaneID.background, title: "Background Tasks", systemImage: "clock.arrow.2.circlepath", tint: .indigo,
            sortOrder: 990
        ) {
            BackgroundTasksPane()
        })
        registry.register(settings: SettingsPaneDescriptor(
            id: ShellPaneID.about, title: "About", systemImage: "info.circle", sortOrder: 1000
        ) {
            AboutSettingsPane()
        })
        // iOS takes background launch handlers only before the app finishes launching, which is now.
        if BackgroundWorkHost.hostsBackgroundWork { services.backgroundWork.registerSystemLaunches() }
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        // The capture arbiter starts permissive; apply the saved privacy switch.
        services.capture.camerasAllowed = services.settings[CoreSettings.cameraEnabled]
        if LaunchOptions.current().demoContent {
            DemoContent.install(services: services, registry: registry)
        }
    }
}
