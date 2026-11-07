import HomePadCore
import Observation
import UIKit

/// Keeps recent still images for a set of cameras, refreshed every few
/// seconds while a face is on screen. Cameras without a snapshot (the demo
/// home) get a generated placeholder scene instead.
@MainActor
@Observable
final class CameraSnapshots {
    private(set) var images: [HomeCamera.ID: UIImage] = [:]
    private(set) var updatedAt: [HomeCamera.ID: Date] = [:]
    /// True once every camera has had its first snapshot or placeholder.
    private(set) var hasLoaded = false
    /// Cameras whose picture is a generated placeholder.
    private(set) var placeholders: Set<HomeCamera.ID> = []

    /// Refreshes until the calling task is cancelled.
    func run(cameras: [HomeCamera], service: any SmartHomeService, every interval: TimeInterval) async {
        while !Task.isCancelled {
            for (index, camera) in cameras.enumerated() {
                await refresh(camera, index: index, service: service)
            }
            hasLoaded = true
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func refresh(_ camera: HomeCamera, index: Int, service: any SmartHomeService) async {
        if let data = try? await service.snapshot(cameraID: camera.id), let image = UIImage(data: data) {
            images[camera.id] = image
            placeholders.remove(camera.id)
        } else if images[camera.id] == nil {
            images[camera.id] = await Self.placeholder(index: index)
            placeholders.insert(camera.id)
        }
        updatedAt[camera.id] = Date()
    }

    /// A demo scene standing in for a camera feed, rendered off the main thread.
    private static func placeholder(index: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            DemoPhotoScenes.render(index + 1, side: 720).map { UIImage(cgImage: $0.image) }
        }.value
    }
}
