import CoreImage
import Foundation
@preconcurrency import Vision

/// An embedding of one face, with the liveness verdict when depth was available.
struct FaceEmbeddingSample: Sendable {
    var embedding: [Float]
    /// Nil when no depth was available (RGB-only iPads, or depth too sparse).
    var liveness: LivenessResult?
    var yaw: Double?
    var pitch: Double?
    /// How long the sample waited for a frame with depth, for the presence trace.
    var depthWaitSeconds: TimeInterval?
    /// The unbroken single-face track of the frame (`FaceTrackContinuity`). Nil
    /// off ARKit face tracking or without exactly one tracked face.
    var trackID: UUID?
    /// How many faces Vision found in the frame. Nil when not counted.
    var visibleFaces: Int?
    /// For the presence trace, when the face failed the liveness check: the
    /// grid read through other mappings (`LivenessAlignmentCheck`). Numbers only.
    var livenessCheck: String?
    /// Mean brightness of the embedded crop, 0 to 1 as stored (gamma encoded).
    var cropLuma: Double?
}

/// Turns a detected face into an embedding with Vision feature prints.
///
/// The face is cropped square, rotated so the eyes are level (using the roll
/// angle from face detection) and scaled to a fixed size before the feature
/// print runs. Enrollment and recognition use this same path, so crops match.
///
/// Feature prints are a general image descriptor, not a face identity model.
/// iOS has no public face identity API, so accuracy is limited (see README).
final class FaceEmbedder {
    /// Feature print revision recorded with templates.
    static let featurePrintRevision = VNGenerateImageFeaturePrintRequestRevision2
    static let cropSide: CGFloat = 192
    /// A crop darker than this tells nothing about who it is (`cropLuma`).
    /// In a 1 lux room, crops at 0.10 or darker scored 0.61 to 0.75 against a
    /// face that scores 0.80 to 1.00 in daylight, and darker ones under 0.55,
    /// enough to call the owner a stranger. Brightened first they scored 0.63
    /// to 0.86, so brightening does not rescue them. From 0.22 they matched
    /// at 0.86 to 0.88. The screen's own light brings a face there.
    static let minimumCropLuma = 0.15

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let request: VNGenerateImageFeaturePrintRequest = {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = FaceEmbedder.featurePrintRevision
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    /// Embeds `face` from `frame`, and checks liveness against `depth` when given.
    func embed(_ face: VNFaceObservation, in frame: SensorFrame, depth: DepthMap?) -> FaceEmbeddingSample? {
        guard let crop = alignedCrop(face, in: frame), let embedding = featurePrint(of: crop) else { return nil }
        let yaw = face.yaw?.doubleValue
        let liveness = depth.map { DepthLiveness.evaluate(faceBox: face.boundingBox, in: frame, depth: $0, yaw: yaw) }
        var sample = FaceEmbeddingSample(
            embedding: embedding, liveness: liveness,
            yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue
        )
        sample.cropLuma = meanLuma(of: crop)
        return sample
    }

    /// The unit-length feature print of a crop.
    private func featurePrint(of crop: CIImage) -> [Float]? {
        let side = Self.cropSide
        guard let image = context.createCGImage(crop, from: CGRect(x: 0, y: 0, width: side, height: side)) else { return nil }
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let vector = Self.floats(from: observation) else { return nil }
        return FaceMatcher.normalized(vector)
    }

    /// Mean brightness of the crop, 0 to 1 as stored (gamma encoded).
    private func meanLuma(of crop: CIImage) -> Double? {
        let area = CGRect(x: 0, y: 0, width: Self.cropSide, height: Self.cropSide)
        let average = crop.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: area)])
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: sRGB)
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
    }

    /// Runs the crop and the feature print once on a blank frame in the format
    /// cameras deliver, so the first real sample does not wait for the model to
    /// load and the Core Image kernels to compile. Device traces showed the
    /// first face tracking frame of a launch holding up the frames behind it by
    /// about a quarter second, and later visits not.
    func warmUp() {
        guard let buffer = Self.blankFrame(width: 640, height: 480) else { return }
        let frame = SensorFrame(pixelBuffer: buffer, orientation: .right, timestamp: 0, source: .trueDepth)
        let face = VNFaceObservation(
            requestRevision: VNDetectFaceRectanglesRequestRevision3,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), roll: 0.1, yaw: 0, pitch: 0
        )
        _ = embed(face, in: frame, depth: nil)
    }

    /// A mid-gray 4:2:0 full-range buffer, the format of ARKit and capture frames.
    static func blankFrame(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                  attributes, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        for plane in 0..<CVPixelBufferGetPlaneCount(buffer) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
            memset(base, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane))
        }
        return buffer
    }

    private func alignedCrop(_ face: VNFaceObservation, in frame: SensorFrame) -> CIImage? {
        let upright = CIImage(cvPixelBuffer: frame.pixelBuffer).oriented(frame.orientation)
        let box = face.boundingBox.denormalized(in: upright.extent)
        let side = max(box.width, box.height) * 1.2
        guard side >= 24 else { return nil }
        let roll = CGFloat(face.roll?.doubleValue ?? 0)
        let scale = Self.cropSide / side
        let transform = CGAffineTransform(translationX: -box.midX, y: -box.midY)
            .concatenating(CGAffineTransform(rotationAngle: -roll))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: Self.cropSide / 2, y: Self.cropSide / 2))
        return upright.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: Self.cropSide, height: Self.cropSide))
    }

    static func floats(from observation: VNFeaturePrintObservation) -> [Float]? {
        let data = observation.data
        switch observation.elementType {
        case .float:
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .double:
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).map(Float.init) }
        default:
            return nil
        }
    }
}
