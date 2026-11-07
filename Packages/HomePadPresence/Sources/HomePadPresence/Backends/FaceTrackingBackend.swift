@preconcurrency import ARKit
import Foundation
import HomePadCore
import ImageIO
import simd

/// ARKit face tracking on the TrueDepth camera. Gives metric distance, gaze
/// and several faces, and works in the dark because TrueDepth is infrared.
///
/// ARKit always runs the camera at its format's rate (30 or 60 fps). The
/// backend picks the slowest format and analyzes only `framesPerSecond` frames.
@MainActor
final class FaceTrackingBackend: SensingBackend {
    let kind = BackendKind.faceTracking
    private let session = ARSession()
    private let receiver: FrameReceiver
    /// The analysis queue ARKit delivers frames on.
    private let queue: DispatchQueue

    init(analyzer: FrameAnalyzer, queue: DispatchQueue) {
        receiver = FrameReceiver(analyzer: analyzer)
        self.queue = queue
        session.delegateQueue = queue
        session.delegate = receiver
    }

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    func start(
        framesPerSecond: Double,
        deliver: @escaping @MainActor (FrameAnalysis) -> Void,
        failed: @escaping @MainActor (String) -> Void
    ) {
        guard Self.isSupported else {
            failed("Face tracking is not supported on this iPad.")
            return
        }
        if let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            receiver.orientation = OrientationTracker(device: device)
        }
        receiver.throttle.setFrameRate(framesPerSecond)
        receiver.deliver = deliver
        receiver.failed = failed
        let analyzer = receiver.analyzer
        queue.async { analyzer.startFaceTracking() }

        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        configuration.isLightEstimationEnabled = true
        let slowest = ARFaceTrackingConfiguration.supportedVideoFormats.min {
            ($0.framesPerSecond, $0.imageResolution.width) < ($1.framesPerSecond, $1.imageResolution.width)
        }
        if let slowest { configuration.videoFormat = slowest }
        let format = configuration.videoFormat
        PresenceTrace.trace.log("face tracking format \(Int(format.imageResolution.width))x\(Int(format.imageResolution.height)) "
            + "at \(format.framesPerSecond) fps")
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func setFrameRate(_ framesPerSecond: Double) {
        receiver.throttle.setFrameRate(framesPerSecond)
    }

    func stop() {
        session.pause()
    }

    /// ARKit closes the camera shortly after `pause()`. Give it a moment before
    /// reporting the camera free, so the next session does not start too early.
    func stop(released: @escaping @MainActor () -> Void) {
        session.pause()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            released()
        }
    }
}

/// Receives ARKit frames on the analysis queue. Frames are processed inside
/// the callback and never retained, so ARKit can recycle its buffers.
private final class FrameReceiver: NSObject, ARSessionDelegate, @unchecked Sendable {
    let analyzer: FrameAnalyzer
    let throttle = FrameThrottle(framesPerSecond: 10)
    var orientation: OrientationTracker?
    var deliver: (@MainActor (FrameAnalysis) -> Void)?
    var failed: (@MainActor (String) -> Void)?
    /// When the last depth signature was taken.
    private var lastSignatureAt: TimeInterval = -.infinity

    init(analyzer: FrameAnalyzer) {
        self.analyzer = analyzer
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let deliver else { return }
        // TrueDepth measures depth on only some frames (about 15 a second), so
        // the analyzed frame rarely carries any. Every depth map is read, so the
        // person stays followed and the next face sample has fresh depth for
        // its liveness check. Without this almost every sample lacked depth.
        // The face track is checked on every frame too, also the skipped ones,
        // so a face lost and found again between two analyzed frames ends it.
        let faceTrackID = analyzer.followFaces(
            Self.arkitFaces(in: frame), depth: frame.capturedDepthData,
            image: ImageGeometry(size: frame.camera.imageResolution, intrinsics: frame.camera.intrinsics),
            at: frame.timestamp
        )
        guard throttle.accept(frame.timestamp) else { return }
        let sensorFrame = SensorFrame(
            pixelBuffer: frame.capturedImage,
            orientation: orientation?.orientation ?? .right,
            timestamp: frame.timestamp,
            source: .trueDepth,
            horizontalFOVDegrees: Self.horizontalFOV(frame.camera),
            brightnessValue: (frame.exifData[kCGImagePropertyExifBrightnessValue as String] as? NSNumber)?.doubleValue,
            arkitAmbientIntensity: frame.lightEstimate.map { Double($0.ambientIntensity) },
            trackedFaces: Self.faces(in: frame),
            faceTrackID: faceTrackID,
            depthSignature: dueSignature(frame, track: faceTrackID)
        )
        let analysis = analyzer.analyze(sensorFrame, backend: .faceTracking)
        Task { @MainActor in deliver(analysis) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        if let failed { Task { @MainActor in failed(message) } }
    }


    /// A depth signature of the one tracked face, when the analyzer wants one
    /// and the last is `depthSignatureInterval` old.
    private func dueSignature(_ frame: ARFrame, track: UUID?) -> DepthSignatureSample? {
        guard let interval = analyzer.options.depthSignatureInterval, track != nil,
              frame.timestamp - lastSignatureAt >= interval else { return nil }
        let anchors = frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter(\.isTracked)
        guard anchors.count == 1, let anchor = anchors.first, let sample = Self.depthSignature(of: anchor) else { return nil }
        lastSignatureAt = frame.timestamp
        return sample
    }

    /// The face mesh as a signature, when the face is near its resting
    /// expression. The eyes are left out of the expression: blinks and
    /// glances barely move the mesh.
    static func depthSignature(of anchor: ARFaceAnchor) -> DepthSignatureSample? {
        let expression = anchor.blendShapes
            .filter { !$0.key.rawValue.hasPrefix("eye") }
            .map { $0.value.doubleValue }
            .max() ?? 0
        guard expression <= DepthSignature.maximumExpression,
              let signature = DepthSignature(vertices: anchor.geometry.vertices) else { return nil }
        return DepthSignatureSample(signature: signature, expression: expression)
    }

    /// Every tracked face anchor: its position in camera space for the face
    /// track, and where it is in the captured image for the depth person
    /// tracker. ARKit projects the anchor into the captured image's own
    /// orientation (landscape right) and size.
    static func arkitFaces(in frame: ARFrame) -> [ARKitFace] {
        let size = frame.camera.imageResolution
        let toCamera = simd_inverse(frame.camera.transform)
        return frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter(\.isTracked).map { anchor in
            let world = SIMD3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
            let pixel = frame.camera.projectPoint(world, orientation: .landscapeRight, viewportSize: size)
            let column = (toCamera * anchor.transform).columns.3
            let position = SIMD3(column.x, column.y, column.z)
            let image = FaceInImage(
                point: CGPoint(x: pixel.x / size.width, y: pixel.y / size.height),
                distanceMeters: Double(abs(position.z))
            )
            return ARKitFace(anchor: anchor.identifier, position: position, image: image)
        }
    }

    /// Distance and gaze for every tracked face, in camera space.
    static func faces(in frame: ARFrame) -> [DetectedFace] {
        let toCamera = simd_inverse(frame.camera.transform)
        return frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter(\.isTracked).map { anchor in
            let relative = toCamera * anchor.transform
            let position = SIMD3(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z)
            let gaze = relative * SIMD4(anchor.lookAtPoint, 1)
            let looking = GazeMath.isLookingAtScreen(face: position, gazeTarget: SIMD3(gaze.x, gaze.y, gaze.z))
            return DetectedFace(distanceMeters: Double(simd_length(position)), isLookingAtScreen: looking)
        }
    }

    static func horizontalFOV(_ camera: ARCamera) -> Double? {
        let focal = Double(camera.intrinsics[0][0])
        let width = Double(camera.imageResolution.width)
        guard focal > 0 else { return nil }
        return 2 * atan(width / 2 / focal) * 180 / .pi
    }
}
