import Foundation
import UIKit

/// A still image taken from the shared feed.
struct CapturedStill {
    let jpeg: Data
    let image: UIImage
    let isDemo: Bool
}

/// Errors Camera Lab shows to people (and returns to the assistant).
enum CameraLabError: LocalizedError, Equatable {
    case cameraUnavailable(String)
    case noFrame
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable(let reason): reason
        case .noFrame: "The camera did not deliver a picture in time."
        case .encodingFailed: "Could not encode the picture."
        }
    }
}

/// Takes one still: claims the camera if needed, waits for exposure to settle,
/// encodes a JPEG, and releases. Shares the feed with Security Camera when both
/// want the same camera.
@MainActor
struct StillGrabber {
    let broker: CameraBroker

    func grab(owner: String, title: String, camera: CameraPosition = .back, maxDimension: CGFloat = 1600) async throws -> CapturedStill {
        let alreadyHeld = broker.isHeld(by: owner)
        if case .denied(let reason) = broker.acquire(owner, title: title, camera: camera) {
            throw CameraLabError.cameraUnavailable(reason)
        }
        defer { if !alreadyHeld { broker.release(owner) } }
        guard let hub = broker.hub else { throw CameraLabError.cameraUnavailable("The camera is not available.") }
        // A cold camera needs a moment for auto exposure and focus.
        let settle: TimeInterval = hub.latestFrame == nil ? 1.0 : 0
        guard let frame = await hub.frame(after: Date().addingTimeInterval(settle), timeout: .seconds(5)) else {
            throw CameraLabError.noFrame
        }
        guard let jpeg = FrameEncoder.jpeg(from: frame.pixelBuffer, maxDimension: maxDimension, quality: 0.8),
              let image = UIImage(data: jpeg) else {
            throw CameraLabError.encodingFailed
        }
        return CapturedStill(jpeg: jpeg, image: image, isDemo: frame.isDemo)
    }
}
