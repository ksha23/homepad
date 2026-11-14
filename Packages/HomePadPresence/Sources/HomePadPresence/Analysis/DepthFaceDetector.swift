import CoreGraphics
import Foundation
import ImageIO
import simd
@preconcurrency import Vision

/// Finds faces in the depth map alone by drawing it as a lit surface and
/// running Vision's face detector on that picture: a face's shape, lit, looks
/// like a face, with no light in the room and no camera image. The dot
/// projector is all it uses.
///
/// The nearest point of the followed head was a poor anchor for the face:
/// the person was often picked up from a moving hand or shoulder, and the
/// crop landed wherever that was. A face box from the face's own shape is a
/// better one (`DepthFaceFinder.search`).
///
/// Used on the analysis queue only.
final class DepthFaceDetector {
    /// Every this many pixels of the depth map are drawn, so the picture costs
    /// a quarter of the map's pixels. A face at half a meter is still about
    /// 60 pixels wide in it.
    static let step = 2
    /// Depths drawn, in meters. Nearer or farther is black.
    static let nearMeters: Float = 0.2
    static let farMeters: Float = 1.6

    private let request: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()

    /// A face found in the shaded depth: its box in the native depth map,
    /// normalized with a top-left origin, and the roll Vision measured.
    struct Face: Sendable {
        var box: CGRect
        var rollDegrees: Double?
    }

    /// The largest face in the shaded depth, if any. `orientation` turns the
    /// native map upright, as for the camera's frames.
    func detect(in map: DepthMap, orientation: CGImagePropertyOrientation) -> (face: Face?, shaded: CGImage?) {
        guard let shaded = Self.shade(map) else { return (nil, nil) }
        let handler = VNImageRequestHandler(cgImage: shaded, orientation: orientation)
        guard (try? handler.perform([request])) != nil,
              let best = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return (nil, shaded) }
        // Vision's box is in the upright picture with a bottom-left origin.
        let upright = CGRect(x: best.boundingBox.minX, y: 1 - best.boundingBox.maxY,
                             width: best.boundingBox.width, height: best.boundingBox.height)
        let box = Self.native(upright, orientation)
        let roll = best.roll.map { $0.doubleValue * 180 / .pi }
        return (Face(box: box, rollDegrees: roll), shaded)
    }

    /// The depth map as a grayscale picture of its surface lit from the
    /// camera, a little from above: brightness is how squarely each spot
    /// faces the light. Spots with no depth, or out of range, are black.
    static func shade(_ map: DepthMap) -> CGImage? {
        let step = Self.step
        let width = map.width / step
        let height = map.height / step
        guard width > 2, height > 2 else { return nil }
        let focal = Float(map.focalLengthOrDefault)
        let light = simd_normalize(SIMD3<Float>(0.15, -0.35, -1))
        var bytes = [UInt8](repeating: 0, count: width * height)
        for row in 1..<(height - 1) {
            for column in 1..<(width - 1) {
                let z = map.depth(column: column * step, row: row * step)
                guard z.isFinite, z > nearMeters, z < farMeters else { continue }
                let left = map.depth(column: (column - 1) * step, row: row * step)
                let right = map.depth(column: (column + 1) * step, row: row * step)
                let up = map.depth(column: column * step, row: (row - 1) * step)
                let down = map.depth(column: column * step, row: (row + 1) * step)
                guard left.isFinite, right.isFinite, up.isFinite, down.isFinite else { continue }
                // Meters across two neighbors at this depth.
                let span = 2 * Float(step) * z / focal
                let dzdx = (right - left) / span
                let dzdy = (down - up) / span
                // Too steep is an edge between a surface and what is behind it.
                guard abs(dzdx) < 4, abs(dzdy) < 4 else { continue }
                let normal = simd_normalize(SIMD3<Float>(dzdx, dzdy, -1))
                let brightness = max(0, simd_dot(normal, light))
                bytes[row * width + column] = UInt8(min(255, brightness * 255))
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// A rect in the upright picture (top-left origin) back in the native map.
    static func native(_ rect: CGRect, _ orientation: CGImagePropertyOrientation) -> CGRect {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)].map { native($0, orientation) }
        return CGRect(
            x: min(corners[0].x, corners[1].x), y: min(corners[0].y, corners[1].y),
            width: abs(corners[0].x - corners[1].x), height: abs(corners[0].y - corners[1].y)
        )
    }

    /// The inverse of `RecognitionDebugRenderer.upright`.
    static func native(_ point: CGPoint, _ orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .up, .upMirrored: point
        case .down, .downMirrored: CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .right, .rightMirrored: CGPoint(x: point.y, y: 1 - point.x)
        case .left, .leftMirrored: CGPoint(x: 1 - point.y, y: point.x)
        }
    }
}
