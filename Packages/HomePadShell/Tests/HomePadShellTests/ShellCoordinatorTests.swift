import Foundation
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadShell

/// The coordinator connects the navigator to the rest of the app.
@MainActor
@Suite struct ShellCoordinatorTests {
    /// The assistant reads which app is on screen from `AppServices`.
    @Test func theAppOnScreenReachesTheServices() throws {
        let defaults = try #require(UserDefaults(suiteName: "homepad.shell.coordinator.\(UUID().uuidString)"))
        let services = AppServices(settings: SettingsStore(defaults: defaults))
        let registry = ModuleRegistry()
        registry.register(app: AppDescriptor(id: "recipes", title: "Recipes", systemImage: "fork.knife", category: .kitchen) { EmptyView() })
        let dependencies = KioskDependencies(
            clock: { Date() }, presence: { .empty }, brightness: FakeBrightness(), health: DeviceHealthMonitor(live: false),
            setIdleTimerDisabled: { _ in }, brightenDuration: 0, darkenDuration: 0, tickInterval: .seconds(3600)
        )
        let coordinator = ShellCoordinator(services: services, registry: registry, launchOptions: LaunchOptions(),
                                           kioskDependencies: dependencies)
        coordinator.navigator.open(appID: "recipes")
        #expect(services.visibleAppID == "recipes")
        coordinator.navigator.goAmbient()
        #expect(services.visibleAppID == nil)
    }

    /// Home Assistant reads what fills the screen, the face and the power from `AppServices`.
    @Test func theKioskStatusReachesTheServices() throws {
        let defaults = try #require(UserDefaults(suiteName: "homepad.shell.coordinator.\(UUID().uuidString)"))
        let services = AppServices(settings: SettingsStore(defaults: defaults))
        let registry = ModuleRegistry()
        registry.register(app: AppDescriptor(id: "recipes", title: "Recipes", systemImage: "fork.knife", category: .kitchen) { EmptyView() })
        registry.register(face: FaceDescriptor(id: "faces.night", title: "Night", systemImage: "moon") { EmptyView() })
        let health = DeviceHealthMonitor(live: false)
        health.update(power: .charging, batteryLevel: 0.5, thermalState: .nominal)
        let dependencies = KioskDependencies(
            clock: { Date() }, presence: { .empty }, brightness: FakeBrightness(0.6), health: health,
            setIdleTimerDisabled: { _ in }, brightenDuration: 0, darkenDuration: 0, tickInterval: .seconds(3600)
        )
        let coordinator = ShellCoordinator(services: services, registry: registry, launchOptions: LaunchOptions(),
                                           kioskDependencies: dependencies)
        coordinator.start()
        #expect(services.kioskStatus.surface == .face)
        #expect(services.kioskStatus.faceID == "faces.night")
        #expect(services.kioskStatus.power == .charging)
        #expect(services.kioskStatus.batteryLevel == 0.5)
        #expect(services.kioskStatus.brightness != nil)
        coordinator.navigator.open(appID: "recipes")
        coordinator.kiosk.tick()
        #expect(services.kioskStatus.surface == .app)
        coordinator.navigator.goHome()
        coordinator.kiosk.tick()
        #expect(services.kioskStatus.surface == .homeScreen)
    }
}
