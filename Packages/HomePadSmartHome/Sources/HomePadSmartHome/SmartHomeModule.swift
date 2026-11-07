import HomePadCore
import HomePadUI
import SwiftUI

/// HomeKit and Home Assistant: the unified smart home service, the Home app with
/// its cameras, the Dashboards app, the doorbell overlay, Control Center tiles,
/// widgets, the "Smart Home" settings pane and the raw Home Assistant assistant tool.
public enum SmartHomeModule: HomePadModule {
    public static let id = "smarthome"
    static let homeAppID = "home"
    /// Not an app: cameras live in the Home app, as on HomeView. The ID opens
    /// them there, for the camera widget, faces, the doorbell and Siri.
    static let camerasAppID = "cameras"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let service = UnifiedSmartHomeService(services: services)
        services.smartHome = service
        SmartHomeSharing.register(service: service, settings: services.settings, in: registry)
        let device = HomeAssistantDevice(services: services, registry: registry, smartHome: service)
        service.homeAssistantDevice = device
        let navigator = DashboardNavigator(events: services.events)
        let doorbell = DoorbellPresenter(settings: services.settings, events: services.events,
                                         chime: DoorbellChime(services: services))
        doorbell.startListening()
        let launch = SmartHomeLaunchOptions.current
        if let favorites = launch.favoriteIDs {
            services.settings[SmartHomeSettings.favoriteAccessoryIDs] = favorites
        }

        /// Every view gets the module's own service, navigator and Home Assistant device, and the doorbell,
        /// whose screen covers every other camera feed while it shows.
        func hosted<V: View>(_ view: V) -> some View {
            view.environment(service).environment(navigator).environment(device).environment(doorbell)
        }

        registry.register(app: AppDescriptor(id: homeAppID, title: "Home", systemImage: "house.fill", tint: .orange,
                                             category: .home, sortOrder: 10) {
            hosted(HomeAppView(initialDetailID: launch.accessoryID, initialRoom: launch.room, initialCameraID: launch.cameraID))
        })
        registry.register(redirect: AppRedirect(id: camerasAppID, opens: homeAppID) {
            service.requestsAllCameras = true
        })
        registry.register(app: AppDescriptor(id: DashboardNavigator.appID, title: "Dashboards", systemImage: "rectangle.3.group.fill",
                                             tint: .teal, category: .home, sortOrder: 12) {
            hosted(DashboardsAppView(fixtureURL: launch.dashboardFixtureURL))
        })
        registry.register(overlay: OverlayDescriptor(id: "smarthome.doorbell", zIndex: 50) {
            hosted(DoorbellOverlayView(presenter: doorbell))
        })
        // Below the doorbell, which is more urgent than a message from an automation.
        registry.register(overlay: OverlayDescriptor(id: "smarthome.homeAssistant.notification", zIndex: 45) {
            hosted(HomeAssistantNotificationOverlay(device: device))
        })
        registry.register(control: ControlDescriptor(id: "smarthome.scenes", title: "Scenes", systemImage: "sparkles", size: .large, sortOrder: 40) {
            hosted(FavoriteScenesControl())
        })
        registry.register(control: ControlDescriptor(id: "smarthome.accessories", title: "Home", systemImage: "house.fill", size: .large, sortOrder: 41) {
            hosted(FavoriteAccessoriesControl())
        })
        // Tall shows more rows of controls. Edit Widget picks which ones.
        registry.register(widget: WidgetDescriptor(id: "smarthome.favorites", title: "Home Favorites", systemImage: "star.fill",
                                                   supportedSizes: [.small, .medium, .large, .tall], opensApp: Self.homeAppID) {
            hosted(FavoritesWidget(size: $0))
        } settings: {
            hosted(FavoritesWidgetSettingsView(settings: $0))
        })
        registry.register(widget: WidgetDescriptor(id: "smarthome.scenes", title: "Scenes", systemImage: "sparkles",
                                                   supportedSizes: [.small, .medium], opensApp: Self.homeAppID) {
            hosted(ScenesWidget(size: $0))
        })
        // A doorbell ring asks a widget stack to show the camera, and it stays a while after the ring's banner closes.
        registry.register(widget: WidgetDescriptor(id: "smarthome.camera", title: "Camera", systemImage: "video.fill", opensApp: Self.camerasAppID,
                                                   relevance: { _ in
            doorbell.ring.map { .needsLook(until: $0.rangAt.addingTimeInterval(WidgetRelevance.afterEvent)) }
        }) {
            hosted(CameraSnapshotWidget(size: $0))
        })
        registry.register(settings: SettingsPaneDescriptor(id: SmartHomeSettingsView.paneID, title: "Smart Home",
                                                           systemImage: "house.fill", tint: .orange, sortOrder: 30, adminOnly: true) {
            hosted(SmartHomeSettingsView())
        })
        registry.register(tool: HomeAssistantServiceTool.make(service: service))
        registry.register(screenContext: HomeScreenContext.provider(service: service))
        registry.register(screenContext: HomeScreenContext.doorbell(doorbell, service: service))
        SmartHomeCameraView.renderer = { cameraID, mode in
            AnyView(hosted(SharedCameraView(cameraID: cameraID, mode: mode)))
        }
        if launch.showsSettings {
            registry.register(overlay: OverlayDescriptor(id: "smarthome.debug.settings", zIndex: 40) {
                hosted(NavigationStack { SmartHomeSettingsView().navigationTitle("Smart Home") })
            })
        }
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        let service = services.smartHome as? UnifiedSmartHomeService
        service?.start()
        service?.homeAssistantDevice?.start()
        if let cameraID = SmartHomeLaunchOptions.current.doorbellCameraID {
            Task {
                try? await Task.sleep(for: .seconds(2))
                services.events.post(.doorbellRang(cameraID: cameraID))
            }
        }
    }
}
