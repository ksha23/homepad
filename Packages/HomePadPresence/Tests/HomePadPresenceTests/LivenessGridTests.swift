import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HomePadPresence

/// The liveness grid must land on the face in the depth map, whichever way
/// the camera's buffer is turned (the 11-inch's front camera is on the short
/// edge, the M4's on the long edge), and when ARKit's 16:9 image covers only
/// the middle band of a 4:3 depth map.
@Suite struct LivenessGridTests {
    /// ARKit's face tracking image, native (unrotated) size.
    private let imageWidth = 1280
    private let imageHeight = 720
    /// A face box side in image pixels, about a face at 0.6 m.
    private let faceSide = 160.0
    /// Where the face is in the native image, normalized, top-left origin:
    /// near an edge, where reading the depth map one to one goes wrong most.
    private let nativeFace = CGPoint(x: 0.35, y: 0.1)

    /// A dark room: no depth behind the face. A face 0.6 m away whose nose is
    /// 4 cm nearer than its edge, where `nativeFace` lies in a 640x480 map.
    private func depthMap() -> DepthMap {
        let width = 640
        let height = 480
        // The 16:9 image is the middle three quarters of the 4:3 map's height.
        let centerColumn = Double(nativeFace.x) * Double(width)
        let centerRow = (0.125 + 0.75 * Double(nativeFace.y)) * Double(height)
        // Two image pixels per depth pixel on both axes.
        let radius = faceSide / 2 / 2
        var meters = [Float](repeating: .nan, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let dx = Double(column) + 0.5 - centerColumn
                let dy = Double(row) + 0.5 - centerRow
                let reach = (dx * dx + dy * dy) / (radius * radius)
                guard reach <= 1 else { continue }
                meters[row * width + column] = Float(0.6 - 0.04 * (1 - reach))
            }
        }
        return DepthMap(width: width, height: height, meters: meters)
    }

    /// A frame whose buffer is turned by `orientation` to be upright.
    private func frame(_ orientation: CGImagePropertyOrientation) throws -> SensorFrame {
        let buffer = try #require(FaceEmbedder.blankFrame(width: imageWidth, height: imageHeight))
        return SensorFrame(pixelBuffer: buffer, orientation: orientation, timestamp: 0, source: .trueDepth)
    }

    /// The face box Vision reports in the upright image (bottom-left origin)
    /// for the face at `nativeFace`. Worked out by hand per orientation, so the
    /// test also checks the turn back to the native buffer.
    private func uprightBox(_ orientation: CGImagePropertyOrientation) -> CGRect {
        let x = Double(nativeFace.x)
        let y = Double(nativeFace.y)
        let center: CGPoint
        let size: CGSize
        switch orientation {
        case .up:
            center = CGPoint(x: x, y: y)
            size = CGSize(width: Double(imageWidth), height: Double(imageHeight))
        case .down:
            center = CGPoint(x: 1 - x, y: 1 - y)
            size = CGSize(width: Double(imageWidth), height: Double(imageHeight))
        case .right:
            // Turned a quarter clockwise: native rows become upright columns from the right.
            center = CGPoint(x: 1 - y, y: x)
            size = CGSize(width: Double(imageHeight), height: Double(imageWidth))
        default:
            // .left, a quarter counterclockwise.
            center = CGPoint(x: y, y: 1 - x)
            size = CGSize(width: Double(imageHeight), height: Double(imageWidth))
        }
        let width = faceSide / Double(size.width)
        let height = faceSide / Double(size.height)
        let top = Double(center.y) - height / 2
        return CGRect(x: Double(center.x) - width / 2, y: 1 - top - height, width: width, height: height)
    }

    @Test(arguments: [CGImagePropertyOrientation.up, .down, .right, .left])
    func theGridLandsOnTheFace(orientation: CGImagePropertyOrientation) throws {
        let result = DepthLiveness.evaluate(faceBox: uprightBox(orientation), in: try frame(orientation), depth: depthMap())
        #expect(result.isLive)
        #expect(result.validFraction > 0.95)
        let distance = try #require(result.distanceMeters)
        #expect(abs(distance - 0.58) < 0.03)
    }

    /// Read one to one, as before, the grid was off the face on the M4's
    /// traces: mostly no depth (the dark room), and flat.
    @Test(arguments: [CGImagePropertyOrientation.up, .right])
    func readingTheMapOneToOneMissesTheFace(orientation: CGImagePropertyOrientation) throws {
        var map = depthMap()
        map.registration = .identity
        let result = DepthLiveness.evaluate(faceBox: uprightBox(orientation), in: try frame(orientation), depth: map)
        #expect(result.isLive == false)
        #expect(result.validFraction < 0.5)
    }

    /// AVCapture's depth matches its video, so the same aspect reads one to one.
    @Test func matchingAspectReadsOneToOne() throws {
        let buffer = try #require(FaceEmbedder.blankFrame(width: 640, height: 480))
        let frame = SensorFrame(pixelBuffer: buffer, orientation: .up, timestamp: 0, source: .trueDepth)
        let map = DepthMap(width: 320, height: 240, meters: [Float](repeating: 1, count: 320 * 240))
        #expect(DepthLiveness.registration(of: map, for: frame) == .identity)
    }

    /// The trace's check reads the same grid through other mappings and prints only numbers.
    @Test func alignmentCheckPrintsOnlyNumbers() throws {
        var map = depthMap()
        map.registration = .identity
        let text = LivenessAlignmentCheck.describe(faceBox: uprightBox(.up), in: try frame(.up), depth: map, faceMeters: 0.6)
        #expect(text.hasPrefix("liveness grid check: registered valid"))
        #expect(text.contains("face 0.60m"))
    }
}
