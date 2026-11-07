import HomePadCore
import SwiftUI

/// What Core's `SmartHomeCameraView` renders for other modules: the camera's feed,
/// or a placeholder when the ID is unknown.
struct SharedCameraView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    let cameraID: HomeCamera.ID
    let mode: SmartHomeCameraView.Mode

    var body: some View {
        if let camera = service.camera(cameraID) {
            CameraFeedView(camera: camera, purpose: mode == .still ? .still : .grid)
        } else {
            CameraPlaceholder(message: "Camera not available", isLoading: false)
                .environment(\.colorScheme, .dark)
        }
    }
}
