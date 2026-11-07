import HomePadCore
import Testing
@testable import HomePadCameraLab

@MainActor
@Suite struct CameraLabModuleTests {
    @Test func moduleHasID() {
        #expect(CameraLabModule.id == "cameralab")
    }

    @Test func registersAppsSettingsAndTools() {
        let services = AppServices.preview()
        let registry = ModuleRegistry()
        CameraLabModule.register(services: services, registry: registry)
        #expect(registry.app("cameralab") != nil)
        #expect(registry.app("floorplan") != nil)
        #expect(registry.settingsPanes.contains { $0.id == "cameralab" })
        #expect(registry.controls.contains { $0.id == "cameralab.security" })
    }
}
