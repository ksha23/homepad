import HomePadCore
import HomePadUI
import SwiftUI

/// Messages as each recognized member's own Apple ID,
/// through a Mac hub. See docs/COMMS.md.
public enum CommsModule: HomePadModule {
    public static let id = "comms"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let runtime = CommsRuntime(services: services)
        services.household.onMemberIDChange { [weak runtime] old, new in runtime?.moveMember(from: old, to: new) }
        registry.register(app: AppDescriptor(
            id: "messages", title: "Messages", systemImage: "message.fill", tint: .green,
            category: .communication, sortOrder: 10,
            badgeCount: { runtime.store.unreadTotal }
        ) { MessagesAppView().environment(runtime) })
        registry.register(settings: SettingsPaneDescriptor(
            id: "comms", title: "Messages", systemImage: "message.badge", tint: .green, sortOrder: 35
        ) { CommsSettingsView().environment(runtime) })
        registry.register(overlay: OverlayDescriptor(id: "comms.banner", zIndex: 55) {
            MessageBanner().environment(runtime)
        })
        registry.register(control: ControlDescriptor(id: "comms.messages", title: "Messages", sortOrder: 45) {
            MessagesTile().environment(runtime)
        })
        runtimeBox.runtime = runtime
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        runtimeBox.runtime?.start()
    }

    @MainActor private static let runtimeBox = RuntimeBox()

    @MainActor private final class RuntimeBox { var runtime: CommsRuntime? }
}
