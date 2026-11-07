import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

/// Launch arguments win over restored app state: a launch that opens a screen
/// starts every app from its defaults, and an ordinary launch restores.
@MainActor @Suite struct AppStateLaunchTests {
    private func start(_ options: LaunchOptions) -> (ShellCoordinator, AppServices) {
        let defaults = UserDefaults(suiteName: "homepad.shell.appstate.\(UUID().uuidString)")!
        let services = AppServices(settings: SettingsStore(defaults: defaults))
        services.appState[ShellAppState.settingsPane] = ShellPaneID.about
        let dependencies = KioskDependencies(
            clock: Date.init, presence: { .empty }, brightness: FakeBrightness(), health: DeviceHealthMonitor(live: false),
            setIdleTimerDisabled: { _ in }, brightenDuration: 0, darkenDuration: 0, tickInterval: .seconds(3600)
        )
        let coordinator = ShellCoordinator(services: services, registry: ModuleRegistry(),
                                           launchOptions: options, kioskDependencies: dependencies)
        coordinator.start()
        return (coordinator, services)
    }

    @Test func anOrdinaryLaunchRestoresWhatWasSaved() {
        let (_, services) = start(LaunchOptions())
        #expect(!services.appState.keepsStateInMemory)
        #expect(services.appState[ShellAppState.settingsPane] == ShellPaneID.about)
    }

    @Test func aLaunchThatOpensAScreenStartsEveryAppFresh() {
        var options = LaunchOptions()
        options.settingsPane = ShellPaneID.kiosk
        let (coordinator, services) = start(options)
        #expect(services.appState.keepsStateInMemory)
        #expect(services.appState[ShellAppState.settingsPane] == nil)
        #expect(coordinator.navigator.pendingSettingsPane == ShellPaneID.kiosk, "the requested pane wins")
    }
}
