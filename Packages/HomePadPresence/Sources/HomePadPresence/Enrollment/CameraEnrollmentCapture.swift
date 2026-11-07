@preconcurrency import AVFoundation
import Foundation

/// Enrollment frames from the front camera. Uses the TrueDepth camera with
/// depth when available, so each sample also gets a liveness verdict.
@MainActor
final class CameraEnrollmentCapture: EnrollmentCapture {
    let requiresLiveness: Bool
    let featurePrintRevision = FaceEmbedder.featurePrintRevision
    var previewSession: AVCaptureSession? { camera.session }
    private(set) var previewDevice: AVCaptureDevice?

    private let camera: CameraSession
    private let processor = EnrollmentFrameProcessor()
    private let choice: CameraChoice

    init(useTrueDepth: Bool) {
        choice = useTrueDepth && CameraSession.device(for: .trueDepth) != nil ? .trueDepth : .front
        requiresLiveness = choice == .trueDepth
        camera = CameraSession(outputQueue: processor.queue)
        previewDevice = CameraSession.device(for: choice)
    }

    func start(
        onObservation: @escaping @MainActor (EnrollmentObservation) -> Void,
        failed: @escaping @MainActor (String) -> Void
    ) {
        let processor = self.processor
        camera.onFrame = { frame in
            guard let observation = processor.process(frame) else { return }
            Task { @MainActor in onObservation(observation) }
        }
        camera.onDepth = { depth, _, _ in processor.ingest(depth) }
        let configuration = CameraSession.Configuration(
            camera: choice, preset: .hd1280x720, framesPerSecond: 15,
            deliversFrames: true, deliversDepth: choice == .trueDepth
        )
        camera.start(configuration) { result in
            if case .failure = result { failed("The camera could not start.") }
        }
    }

    func stop() {
        camera.stop()
    }
}

/// Runs face detection and embedding on enrollment frames, on its own queue.
private final class EnrollmentFrameProcessor: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.homepad.presence.enrollment", qos: .userInitiated)
    private let detectors = VisionDetectors()
    private let embedder = FaceEmbedder()
    private let throttle = FrameThrottle(framesPerSecond: 6)
    private var depth: DepthMap?

    func ingest(_ data: AVDepthData) {
        depth = DepthMap(data)
    }

    func process(_ frame: SensorFrame) -> EnrollmentObservation? {
        guard throttle.accept(frame.timestamp) else { return nil }
        let faces = detectors.detect(in: frame, faces: true, humans: false, hands: false).faces
        guard let largest = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            return EnrollmentObservation(faceCount: 0, faceWidth: 0, time: frame.timestamp)
        }
        let sample = faces.count == 1 ? embedder.embed(largest, in: frame, depth: depth) : nil
        return EnrollmentObservation(
            faceCount: faces.count, faceWidth: Double(largest.boundingBox.width),
            yaw: largest.yaw?.doubleValue, pitch: largest.pitch?.doubleValue, sample: sample,
            time: frame.timestamp, faceLuma: sample == nil ? nil : Self.meanLuma(of: largest.boundingBox, in: frame)
        )
    }

    /// Mean brightness (0 to 1) of the middle of a face box (Vision coordinates),
    /// from the luma plane of a 4:2:0 frame. Nil for other formats.
    static func meanLuma(of box: CGRect, in frame: SensorFrame) -> Double? {
        let buffer = frame.pixelBuffer
        guard CVPixelBufferIsPlanar(buffer) else { return nil }
        let inner = frame.nativeRect(fromUpright: box.insetBy(dx: box.width * 0.2, dy: box.height * 0.2))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let grid = 12
        var sum = 0
        var count = 0
        for row in 0..<grid {
            for column in 0..<grid {
                // Normalized rects have a bottom-left origin, buffer rows start at the top.
                let x = Int((inner.minX + inner.width * (Double(column) + 0.5) / Double(grid)) * Double(width))
                let y = Int((1 - (inner.minY + inner.height * (Double(row) + 0.5) / Double(grid))) * Double(height))
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                sum += Int(bytes[y * stride + x])
                count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count) / 255 : nil
    }
}
