import HomePadConnect
import HomePadCore
import HomePadShell
import SwiftUI

@main
struct HomePadApp: App {
    @State private var services: AppServices
    @State private var registry: ModuleRegistry

    init() {
        let services = AppServices(settings: SettingsStore(useICloud: true))
        let registry = ModuleRegistry()
        services.makeCurrent()
        ConnectModule.updateShortcutParameters = { HomePadShortcuts.updateAppShortcutParameters() }
        ModuleLoader.load(Modules.all, services: services, registry: registry)
        _services = State(initialValue: services)
        _registry = State(initialValue: registry)
    }

    var body: some Scene {
        WindowGroup {
            root
                .homePadEnvironment(services: services, registry: registry)
                .onOpenURL { url in
                    services.events.post(.custom(name: "openURL", payload: .string(url.absoluteString)))
                }
        }
    }

    /// iPad runs the always-on shell. iPhone and Mac run the companion remote.
    @ViewBuilder
    private var root: some View {
        if AppRole.current == .homePad {
            ShellRootView()
                .persistentSystemOverlays(.hidden)
        } else {
            CompanionRootView()
        }
    }
}
