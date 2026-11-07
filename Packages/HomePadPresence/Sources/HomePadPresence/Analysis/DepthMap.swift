@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// A TrueDepth depth map copied into a plain Float array (meters), so it can be
/// sampled freely without holding the capture buffer.
struct DepthMap: Sendable {
    let width: Int
    let height: Int
    /// Row-major depth in meters, row 0 at the top. NaN where depth is missing.
    let meters: [Float]
    /// How the camera image of the same frame lines up with this map. Nil when
    /// unknown: the two are then matched by aspect ratio where they are used.
    var registration: DepthRegistration?
    /// Focal length in pixels of this map, nil when unknown.
    var focalLength: Double?

    init(width: Int, height: Int, meters: [Float], registration: DepthRegistration? = nil, focalLength: Double? = nil) {
        self.width = width
        self.height = height
        self.meters = meters
        self.registration = registration
        self.focalLength = focalLength
    }

    /// Copies every `step`th pixel of each `step`th row, so a coarse map for
    /// presence costs a few thousand reads instead of a copy of the whole map.
    /// Depth arrives as 16 or 32 bit floats. Disparity is converted first.
    init?(_ depthData: AVDepthData, step: Int = 1) {
        let type = depthData.depthDataType
        let readable = type == kCVPixelFormatType_DepthFloat32 || type == kCVPixelFormatType_DepthFloat16
        let converted = readable ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buffer = converted.depthDataMap
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let step = max(1, step)
        let fullWidth = CVPixelBufferGetWidth(buffer)
        let fullHeight = CVPixelBufferGetHeight(buffer)
        let width = fullWidth / step
        let height = fullHeight / step
        guard width > 0, height > 0 else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let isHalf = converted.depthDataType == kCVPixelFormatType_DepthFloat16
        var meters = [Float](repeating: .nan, count: width * height)
        for row in 0..<height {
            let line = base + (row * step) * rowBytes
            for column in 0..<width {
                let value = isHalf
                    ? Float(line.assumingMemoryBound(to: Float16.self)[column * step])
                    : line.assumingMemoryBound(to: Float32.self)[column * step]
                meters[row * width + column] = value.isFinite && value > 0 ? value : .nan
            }
        }
        self.init(width: width, height: height, meters: meters)
    }

    /// Every `step`th pixel of every `step`th row, keeping the metadata.
    func downsampled(step: Int) -> DepthMap {
        let step = max(1, step)
        guard step > 1 else { return self }
        let columns = max(1, width / step)
        let rows = max(1, height / step)
        var values = [Float](repeating: .nan, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                values[row * columns + column] = meters[(row * step) * width + column * step]
            }
        }
        return DepthMap(
            width: columns, height: rows, meters: values,
            registration: registration, focalLength: focalLength.map { $0 / Double(step) }
        )
    }

    /// The step that brings this map down to about `columns` columns.
    func step(toColumns columns: Int) -> Int {
        max(1, width / max(1, columns))
    }

    /// Focal length in pixels, or one for a 60 degree view across the width
    /// when the map does not know its own.
    var focalLengthOrDefault: Double {
        focalLength ?? Double(width) / 2 / tan(30 * Double.pi / 180)
    }

    /// Depth at a column and row, NaN outside the map.
    func depth(column: Int, row: Int) -> Float {
        guard column >= 0, column < width, row >= 0, row < height else { return .nan }
        return meters[row * width + column]
    }

    /// Depth at a normalized point with a bottom-left origin (Vision and Core Image convention).
    func depth(atNormalized point: CGPoint) -> Float {
        let column = Int((point.x * CGFloat(width)).rounded(.down))
        let row = Int(((1 - point.y) * CGFloat(height)).rounded(.down))
        return depth(column: column, row: row)
    }

    /// A `columns` x `rows` grid of samples over a normalized rect (bottom-left origin).
    /// Row 0 of the result is the bottom of the rect.
    func samples(in rect: CGRect, columns: Int, rows: Int) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = rect.minX + rect.width * (CGFloat(column) + 0.5) / CGFloat(columns)
                let y = rect.minY + rect.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                result.append(depth(atNormalized: CGPoint(x: x, y: y)))
            }
        }
        return result
    }
}
