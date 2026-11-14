import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// What the camera and the depth sensor saw on one frame, drawn small for the
/// recognition debug view on the face screen (`RecognitionDebugOverlay`). It
/// stays on the iPad, in memory, and the next one replaces it. Nothing of it
/// is saved, traced or sent anywhere.
struct RecognitionDebugFrame: @unchecked Sendable {
    /// The camera image, upright.
    var camera: CGImage?
    /// The depth map, upright, nearer in warmer colors, black where it has no depth.
    var depth: CGImage?
    /// The depth face at full resolution, upright, from its nose tip (red) to
    /// `faceSpanMeters` behind it (blue): what the depth signature compares.
    var faceDepth: CGImage?
    /// How old `faceDepth` is when the last search missed, in seconds.
    var faceAgeSeconds: Double?
    /// Faces in the camera image, normalized with a top-left origin.
    var faceBoxes: [CGRect] = []
    /// The followed head in the depth image, normalized with a top-left origin.
    var head: CGRect?
    /// The depth face's nose tip, and how far its signature reaches, in the
    /// depth image, normalized with a top-left origin.
    var nose: CGPoint?
    var reach: CGSize?
    /// True when the nose tip was looked at but its surface was not taken as a face.
    var noseRejected = false
    /// The depth face in words and numbers.
    var depthFace: String
    /// The depth map's native size and whether iOS smoothed it.
    var depthSource: String = "no depth yet"
}

/// Draws `RecognitionDebugFrame`s, on the analysis queue.
final class RecognitionDebugRenderer {
    static let cameraWidth: CGFloat = 320
    static let depthColumns = 160
    /// Depths drawn from red (near) to blue (far), in meters.
    static let nearMeters: Float = 0.3
    static let farMeters: Float = 2.5
    /// The face picture's colors span this much depth behind the nose tip.
    static let faceSpanMeters: Float = 0.08

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let palette: [(UInt8, UInt8, UInt8)] = (0..<256).map { index in
        // Red through yellow and green to blue.
        let hue = Double(index) / 255 * 0.66
        return RecognitionDebugRenderer.rgb(hue: hue)
    }

    func render(
        frame: SensorFrame, faces: [DetectedFace], map: DepthMap?, person: DepthPersonTracker.Person?,
        search: DepthFaceFinder.Search?
    ) -> RecognitionDebugFrame {
        let orientation = frame.orientation
        let face = search?.face
        var result = RecognitionDebugFrame(depthFace: Self.describe(search, person: person))
        result.camera = cameraImage(frame)
        result.faceBoxes = faces.compactMap(\.boundingBox).map { box in
            CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
        if let map {
            result.depth = depthImage(map, orientation: orientation)
            if let person {
                let center = Self.upright(person.center, orientation)
                let radius = Self.uprightSize(person.radius, orientation)
                result.head = CGRect(x: center.x - radius.width, y: center.y - radius.height,
                                     width: radius.width * 2, height: radius.height * 2)
            }
            if face == nil, let point = search?.nosePoint {
                result.nose = Self.upright(point, orientation)
                result.noseRejected = true
            }
            if let face {
                result.nose = Self.upright(face.nosePoint, orientation)
                result.faceDepth = faceImage(map, face: face, orientation: orientation)
                let pixels = DepthFaceFinder.radiusMeters * map.focalLengthOrDefault / face.noseMeters
                result.reach = Self.uprightSize(
                    CGSize(width: pixels / Double(map.width), height: pixels / Double(map.height)), orientation
                )
            }
        }
        return result
    }

    static func describe(_ search: DepthFaceFinder.Search?, person: DepthPersonTracker.Person?) -> String {
        if let face = search?.face {
            return String(format: "found at %.2f m, relief %.1f cm, coverage %.2f, %d points",
                          face.noseMeters, face.relief * 100, face.coverage, face.pointCount)
        }
        if person == nil { return "no person followed to look on" }
        guard let search else { return "not looked for yet" }
        return "not found, " + (search.miss ?? "no reason")
    }

    private func cameraImage(_ frame: SensorFrame) -> CGImage? {
        let upright = CIImage(cvPixelBuffer: frame.pixelBuffer).oriented(frame.orientation)
        let scale = Self.cameraWidth / max(upright.extent.width, 1)
        let small = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(small, from: small.extent)
    }

    private func depthImage(_ map: DepthMap, orientation: CGImagePropertyOrientation) -> CGImage? {
        let step = max(1, map.width / Self.depthColumns)
        let width = map.width / step
        let height = map.height / step
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let span = Self.farMeters - Self.nearMeters
        for row in 0..<height {
            for column in 0..<width {
                let z = map.meters[(row * step) * map.width + column * step]
                let offset = (row * width + column) * 4
                bytes[offset + 3] = 255
                guard z.isFinite else { continue }
                let share = min(max((z - Self.nearMeters) / span, 0), 1)
                let color = palette[Int(share * 255)]
                bytes[offset] = color.0
                bytes[offset + 1] = color.1
                bytes[offset + 2] = color.2
            }
        }
        return uprightImage(bytes, width: width, height: height, orientation: orientation)
    }

    /// The square around the nose tip the signature reaches over, at the map's
    /// full resolution, colored by depth behind the nose tip.
    private func faceImage(_ map: DepthMap, face: DepthFace, orientation: CGImagePropertyOrientation) -> CGImage? {
        let reach = Int((DepthFaceFinder.radiusMeters * map.focalLengthOrDefault / face.noseMeters).rounded(.up))
        let centerColumn = Int(face.nosePoint.x * CGFloat(map.width))
        let centerRow = Int(face.nosePoint.y * CGFloat(map.height))
        let side = reach * 2 + 1
        guard reach > 2 else { return nil }
        let nose = Float(face.noseMeters)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                let offset = (row * side + column) * 4
                bytes[offset + 3] = 255
                let z = map.depth(column: centerColumn - reach + column, row: centerRow - reach + row)
                guard z.isFinite else { continue }
                let behind = z - nose
                guard behind >= -0.01, behind <= Self.faceSpanMeters * 1.25 else { continue }
                let color = palette[Int(min(max(behind / Self.faceSpanMeters, 0), 1) * 255)]
                bytes[offset] = color.0
                bytes[offset + 1] = color.1
                bytes[offset + 2] = color.2
            }
        }
        return uprightImage(bytes, width: side, height: side, orientation: orientation)
    }

    /// RGBA bytes in the native orientation as an upright image.
    private func uprightImage(_ bytes: [UInt8], width: Int, height: Int, orientation: CGImagePropertyOrientation) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let native = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        let upright = CIImage(cgImage: native).oriented(orientation)
        return context.createCGImage(upright, from: upright.extent)
    }

    /// A point in the native map, normalized with a top-left origin, in the
    /// upright image the way `CIImage.oriented` turns it.
    static func upright(_ point: CGPoint, _ orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .up, .upMirrored: point
        case .down, .downMirrored: CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .right, .rightMirrored: CGPoint(x: 1 - point.y, y: point.x)
        case .left, .leftMirrored: CGPoint(x: point.y, y: 1 - point.x)
        }
    }

    static func uprightSize(_ size: CGSize, _ orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored: CGSize(width: size.height, height: size.width)
        default: size
        }
    }

    private static func rgb(hue: Double) -> (UInt8, UInt8, UInt8) {
        let h = hue * 6
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}
