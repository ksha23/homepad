import HomePadCore
import HomePadUI
import SwiftUI

/// Siri and App Intents, the local peer link, intercom, Send to HomePad,
/// Handoff, the Family Board, alert relay, Shortcuts and the companion remote.
public enum ConnectModule: HomePadModule {
    public static let id = "connect"

    /// Set by the app target to its `AppShortcutsProvider.updateAppShortcutParameters`,
    /// so Siri learns scene, accessory and face names. App Shortcuts have to be
    /// declared in the app target, so the package cannot call it directly.
    public static var updateShortcutParameters: @MainActor () -> Void = {}

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let runtime = ConnectRuntime(services: services, registry: registry)
        services.intercom = runtime.intercom
        if runtime.isHomePad {
            services.personalDevices = runtime.approver
            services.phonePhotos = runtime.phonePhotos
            services.memberMusic = runtime.appleMusicLinks
            services.phoneCalendars = runtime.phoneCalendars
        }
        registerApps(runtime, in: registry)
        registerSurfaces(runtime, in: registry)
        registry.register(tools: ConnectTools.make(runtime: runtime))
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        ConnectRuntime.current?.start()
    }

    private static func registerApps(_ runtime: ConnectRuntime, in registry: ModuleRegistry) {
        registry.register(app: AppDescriptor(
            id: "intercom", title: "Intercom", systemImage: "waveform", tint: .green, category: .communication, sortOrder: 20
        ) { IntercomAppView().environment(runtime) })
        registry.register(app: AppDescriptor(
            id: "board", title: "Family Board", systemImage: "note.text", tint: .yellow, category: .productivity, sortOrder: 40
        ) { BoardAppView().environment(runtime) })
        registry.register(app: AppDescriptor(
            id: "shortcuts", title: "Shortcuts", systemImage: "square.2.layers.3d.fill", tint: .indigo, category: .productivity, sortOrder: 60
        ) { ShortcutsAppView().environment(runtime) })
    }

    private static func registerSurfaces(_ runtime: ConnectRuntime, in registry: ModuleRegistry) {
        registry.register(settings: SettingsPaneDescriptor(
            id: "connect", title: "Devices & Sharing", systemImage: "ipad.and.iphone", tint: .green, sortOrder: 30
        ) { DevicesSettingsView().environment(runtime) })

        registry.register(overlay: OverlayDescriptor(id: "connect.handoff", zIndex: 0) { HandoffAnchor().environment(runtime) })
        registry.register(overlay: OverlayDescriptor(id: "connect.share", zIndex: 40) { ShareOverlay().environment(runtime) })
        registry.register(overlay: OverlayDescriptor(id: "connect.intercom", zIndex: 50) { IntercomOverlay().environment(runtime) })
        if runtime.isHomePad {
            registry.register(overlay: OverlayDescriptor(id: "connect.approval", zIndex: 45) { LinkRequestOverlay().environment(runtime) })
        }

        registry.register(control: ControlDescriptor(id: "connect.intercom", title: "Intercom", sortOrder: 40) {
            IntercomTile().environment(runtime)
        })
        registry.register(widget: WidgetDescriptor(
            id: "connect.intercom", title: "Intercom", systemImage: "waveform", supportedSizes: [.small]
        ) { _ in IntercomTile().environment(runtime) })
        registry.register(widget: WidgetDescriptor(
            id: "connect.board", title: "Family Board", systemImage: "note.text", supportedSizes: [.medium, .large]
        ) { _ in BoardWidgetView().environment(runtime) })
    }
}
