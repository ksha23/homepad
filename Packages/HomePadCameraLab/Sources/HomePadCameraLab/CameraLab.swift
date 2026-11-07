import HomePadCore
import Observation

/// Everything Camera Lab shares between its screens, tools and the assistant.
/// One instance is made at launch and handed to every view through the environment.
@MainActor
@Observable
final class CameraLab {
    let services: AppServices
    let capabilities: CameraCapabilities
    let broker: CameraBroker
    let router = CameraLabRouter()
    let security: SecurityCameraController
    let groceries: GrocerySession
    let timelapse: TimelapseController
    let floorPlans = FloorPlanStore()

    init(services: AppServices) {
        self.services = services
        capabilities = CameraCapabilities.detect()
        let broker = CameraBroker(services: services)
        self.broker = broker
        security = SecurityCameraController(services: services, broker: broker)
        groceries = GrocerySession(services: services)
        timelapse = TimelapseController(services: services, broker: broker)
        watchSettings()
    }

    /// One-shot still capture through the shared feed.
    var stills: StillGrabber { StillGrabber(broker: broker) }

    /// Re-applies settings wherever they were changed (the tool screens or the Settings pane).
    private func watchSettings() {
        withObservationTracking {
            _ = services.settings.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.security.settingsChanged()
                self?.watchSettings()
            }
        }
    }
}
