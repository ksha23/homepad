#if os(iOS)
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// A live preview of a running `AVCaptureSession` that stays upright as the
/// iPad rotates, using `AVCaptureDevice.RotationCoordinator`. Claim the
/// camera through `services.capture` before starting the session.
///
///     CameraPreview(session: camera.session, device: camera.device)
///         .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
public struct CameraPreview: UIViewRepresentable {
    private let session: AVCaptureSession
    private let device: AVCaptureDevice?
    private let gravity: AVLayerVideoGravity

    /// - Parameters:
    ///   - session: The capture session to show.
    ///   - device: The camera feeding it, used to keep the picture level.
    ///   - gravity: How the video fills the view. Fills and crops by default.
    public init(session: AVCaptureSession, device: AVCaptureDevice?, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.session = session
        self.device = device
        self.gravity = gravity
    }

    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.show(session)
        view.previewLayer.videoGravity = gravity
        view.attach(device: device)
        return view
    }

    public func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session { view.show(session) }
        view.previewLayer.videoGravity = gravity
        if view.device !== device { view.attach(device: device) }
    }

    /// A view backed by a preview layer.
    public final class PreviewView: UIView {
        override public class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private(set) var device: AVCaptureDevice?
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?
        private var startObserver: NSObjectProtocol?
        /// The latest level angle from the coordinator, applied whenever the
        /// preview has a connection to apply it to.
        private var angle: CGFloat?

        /// The layer only gets a connection once the session is configured,
        /// which is usually after `attach`. So the angle is applied again when
        /// the session starts and on every layout. Without that the picture
        /// stays in the sensor's native orientation, which is sideways on
        /// iPads with the front camera on the long edge (iPad Pro M4).
        func show(_ session: AVCaptureSession) {
            previewLayer.session = session
            if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
            startObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyAngle() }
            }
        }

        func attach(device: AVCaptureDevice?) {
            self.device = device
            observation = nil
            coordinator = nil
            angle = nil
            guard let device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            angle = coordinator.videoRotationAngleForHorizonLevelPreview
            applyAngle()
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    self?.angle = angle
                    self?.applyAngle()
                }
            }
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            applyAngle()
        }

        private func applyAngle() {
            guard let angle, let connection = previewLayer.connection, connection.videoRotationAngle != angle,
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }

        deinit {
            if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
        }
    }
}
#endif
