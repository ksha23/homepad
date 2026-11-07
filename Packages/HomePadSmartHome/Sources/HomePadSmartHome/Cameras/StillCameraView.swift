import HomePadCore
import HomePadUI
import SwiftUI

/// JPEG stills from `snapshot(cameraID:)`, refreshed on an interval while on screen.
/// Each still counts as taken when it arrives, since Home Assistant sends the
/// camera's latest picture and no time with it. A camera that stops answering
/// keeps its last still, which then shows its age.
struct StillCameraView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    let cameraID: HomeCamera.ID
    let interval: Duration
    /// False loads one still and stops, for thumbnails.
    var refreshes = true
    @State private var image: UIImage?
    @State private var capturedAt: Date?
    @Environment(\.cameraContentMode) private var contentMode

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                CameraPlaceholder(message: nil, isLoading: true)
            }
        }
        .preference(key: SnapshotDateKey.self, value: capturedAt)
        .task(id: cameraID) {
            while !Task.isCancelled {
                if let data = try? await service.snapshot(cameraID: cameraID), let decoded = UIImage(data: data) {
                    image = decoded
                    capturedAt = Date()
                }
                guard refreshes else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
