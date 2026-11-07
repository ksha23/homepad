import SwiftUI

/// A camera feed any module can show, for example on the Home Camera face.
/// The Smart Home module installs the renderer at launch, so the view plays
/// HomeKit video, Home Assistant MJPEG or HLS, or the demo feed without other
/// modules importing it. Without a renderer it shows black.
///
///     SmartHomeCameraView(cameraID: camera.id)
///     SmartHomeCameraView(cameraID: camera.id, mode: .still)
public struct SmartHomeCameraView: View {
    public enum Mode: Sendable {
        /// Live video, tuned for grids of several cameras.
        case live
        /// A still that refreshes every few seconds, for widgets and thumbnails.
        case still
    }

    /// Set once by the Smart Home module during registration.
    @MainActor public static var renderer: ((HomeCamera.ID, Mode) -> AnyView)?

    private let cameraID: HomeCamera.ID
    private let mode: Mode

    public init(cameraID: HomeCamera.ID, mode: Mode = .live) {
        self.cameraID = cameraID
        self.mode = mode
    }

    public var body: some View {
        if let renderer = Self.renderer {
            renderer(cameraID, mode)
        } else {
            Color.black
        }
    }
}
