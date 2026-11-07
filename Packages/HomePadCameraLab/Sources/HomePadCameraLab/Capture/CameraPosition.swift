import AVFoundation
import HomePadCore

/// Which iPad camera a Camera Lab tool wants.
enum CameraPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case back
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: "Back Camera"
        case .front: "Front Camera"
        }
    }

    /// The matching camera in Core's capture arbiter.
    var coordinatorCamera: CaptureCoordinator.Camera {
        switch self {
        case .back: .back
        case .front: .front
        }
    }

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: .back
        case .front: .front
        }
    }
}
