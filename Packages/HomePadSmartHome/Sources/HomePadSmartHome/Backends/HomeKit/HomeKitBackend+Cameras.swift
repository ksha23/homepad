import Foundation
@preconcurrency import HomeKit
import HomePadCore
import UIKit

extension HomeKitBackend {
    /// No image data: HomeKit draws camera pictures only inside an on-screen
    /// `HMCameraView`, and has no API that hands out the pixels. Drawing an offscreen
    /// camera view into a JPEG gave a black picture. Other modules show HomeKit
    /// cameras through Core's `SmartHomeCameraView`, which uses the camera view.
    func snapshot(of camera: HomeCamera) async throws -> Data? {
        cameraProfiles[camera.id]?.snapshotControl?.takeSnapshot()
        return nil
    }

    func feed(for camera: HomeCamera, purpose: CameraFeedPurpose, excluding failed: Set<CameraFeedKind>) async -> CameraFeed {
        guard let profile = cameraProfiles[camera.id] else { return .unavailable("This camera is no longer in Apple Home.") }
        return purpose == .still ? .homeKitSnapshot(profile) : .homeKitStream(profile)
    }

    /// Two-way audio needs a speaker on the camera.
    func supportsTalk(_ camera: HomeCamera) -> Bool {
        cameraProfiles[camera.id]?.speakerControl != nil
    }

    /// Sends the iPad's microphone to the camera's speaker while talking.
    func setTalking(_ talking: Bool, camera: HomeCamera) async throws {
        guard let stream = cameraProfiles[camera.id]?.streamControl?.cameraStream else {
            throw SmartHomeError.backend("Start the live view before talking.")
        }
        try await stream.updateAudioStreamSetting(talking ? .bidirectionalAudioAllowed : .incomingAudioAllowed)
    }
}
