import HomePadCore
import HomePadUI
import SwiftUI

/// Root of the whole iPad UI. The app target shows this and nothing else.
/// It builds the shell's coordinator from the environment on first appearance.
public struct ShellRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @State private var coordinator: ShellCoordinator?

    public init() {}

    private var colorScheme: ColorScheme? {
        coordinator?.kiosk.condition == .night ? .dark : services.settings[ShellSettings.appearance].colorScheme
    }

    public var body: some View {
        ZStack {
            // The page color of the appearance, black in Dark and at night.
            Color.screenBackground.ignoresSafeArea()
            if let coordinator {
                ShellContentView(coordinator: coordinator)
            }
        }
        .modifier(ForcedLandscape())
        // Room around every screen. Forced landscape (debug) ignores the
        // window's safe area and adds the margin itself.
        .background(ScreenMarginInstaller(insets: ForcedLandscape.isEnabled ? EdgeInsets() : Theme.Spacing.screenMargin))
        .preferredColorScheme(colorScheme)
        .statusBarHidden()
        .task {
            guard coordinator == nil else { return }
            let coordinator = ShellCoordinator(services: services, registry: registry)
            self.coordinator = coordinator
            coordinator.start()
        }
    }
}
