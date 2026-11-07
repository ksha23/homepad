import Foundation
import HAKit
import HAKit_Mocks
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// What the Home app and the doorbell tell the assistant, so "unlock this
/// door" on a camera finds its lock. Uses the demo home.
@MainActor
@Suite struct HomeScreenContextTests {
    let services: AppServices
    let service: UnifiedSmartHomeService

    init() {
        services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.smarthome.screen.\(UUID().uuidString)")!))
        service = UnifiedSmartHomeService(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: HomeAssistantBackend(store: .inMemory(nil)) { _ in HAMockConnection() },
            homeKit: HomeKitBackend(settings: services.settings)
        )
    }

    private func summary(_ focus: HomeScreenFocus) -> String? {
        HomeScreenContext.summary(of: focus, service: service)
    }

    @Test func theOverviewSaysNothing() {
        #expect(summary(HomeScreenFocus()) == nil)
    }

    @Test func aDoorbellCameraNamesItsLock() throws {
        let text = try #require(summary(HomeScreenFocus(cameraID: "demo:camera.front")))
        #expect(text.hasPrefix("The Front Door camera, live and full screen. Doors beside it: Front Door (lock in the Entryway, "))
    }

    @Test func aCameraWithNoDoorsSaysOnlyItsName() {
        #expect(summary(HomeScreenFocus(cameraID: "demo:camera.yard")) == "The Back Yard camera, live and full screen.")
    }

    @Test func anAccessorysControlsNameIt() throws {
        let text = try #require(summary(HomeScreenFocus(accessoryID: "demo:light.kitchen")))
        #expect(text.hasPrefix("The full-screen controls for Kitchen Lights (light in the Kitchen"))
    }

    @Test func theGridNamesEveryCamera() throws {
        let text = try #require(summary(HomeScreenFocus(showsAllCameras: true)))
        #expect(text.hasPrefix("Every camera in a grid: Front Door, "))
    }

    @Test func theDoorbellSpeaksOverEveryScreenWhileItRings() throws {
        let presenter = DoorbellPresenter(settings: services.settings, events: services.events)
        let provider = HomeScreenContext.doorbell(presenter, service: service)
        #expect(provider.appID == nil)
        #expect(provider.summary() == nil)
        presenter.present(cameraID: "demo:camera.front")
        let text = try #require(provider.summary())
        #expect(text.hasPrefix("The doorbell is ringing, and the Front Door camera shows over the screen. Its door lock: Front Door (lock"))
        presenter.dismiss()
    }
}
