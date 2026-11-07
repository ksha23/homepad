import CoreVideo
import Foundation

/// A tiny grayscale thumbnail of a frame, used for cheap motion detection.
struct LumaGrid: Equatable, Sendable {
    let columns: Int
    let rows: Int
    var values: [UInt8]

    /// Samples a luma grid from a 4:2:0 YCbCr (plane 0) or BGRA pixel buffer.
    /// Each cell averages four pixels, which is enough to ignore sensor noise.
    static func make(from buffer: CVPixelBuffer, columns: Int = 32, rows: Int = 24) -> LumaGrid? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let planar = CVPixelBufferIsPlanar(buffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        let isBGRA = format == kCVPixelFormatType_32BGRA
        guard planar || isBGRA, width >= columns, height >= rows else { return nil }

        let bytes = base.assumingMemoryBound(to: UInt8.self)
        func luma(_ x: Int, _ y: Int) -> Int {
            if isBGRA {
                let p = bytes + y * stride + x * 4
                return (Int(p[2]) * 77 + Int(p[1]) * 150 + Int(p[0]) * 29) >> 8
            }
            return Int(bytes[y * stride + x])
        }
        var values = [UInt8](repeating: 0, count: columns * rows)
        let cellW = width / columns
        let cellH = height / rows
        for row in 0..<rows {
            for column in 0..<columns {
                let x0 = column * cellW + cellW / 4
                let y0 = row * cellH + cellH / 4
                let x1 = column * cellW + cellW * 3 / 4
                let y1 = row * cellH + cellH * 3 / 4
                let sum = luma(x0, y0) + luma(x1, y0) + luma(x0, y1) + luma(x1, y1)
                values[row * columns + column] = UInt8(sum / 4)
            }
        }
        return LumaGrid(columns: columns, rows: rows, values: values)
    }
}

/// Frame differencing on luma grids. Cheap enough to run on every frame.
///
/// A global brightness change (a lamp turning on, auto exposure) shifts every
/// cell by about the same amount, so the mean difference is removed before
/// counting changed cells. Motion is reported when enough cells change.
struct MotionDetector: Sendable {
    var pixelDelta: Int
    var areaFraction: Double
    private var previous: LumaGrid?

    init(pixelDelta: Int = 18, areaFraction: Double = 0.03) {
        self.pixelDelta = pixelDelta
        self.areaFraction = areaFraction
    }

    /// Returns true when this grid differs enough from the previous one.
    mutating func process(_ grid: LumaGrid) -> Bool {
        defer { previous = grid }
        guard let previous else { return false }
        return Self.changedFraction(previous: previous, current: grid, pixelDelta: pixelDelta) >= areaFraction
    }

    mutating func reset() { previous = nil }

    /// Share of cells whose brightness changed by more than `pixelDelta`,
    /// after removing the average (global) change.
    static func changedFraction(previous: LumaGrid, current: LumaGrid, pixelDelta: Int) -> Double {
        guard previous.values.count == current.values.count, !current.values.isEmpty else { return 0 }
        let diffs = zip(current.values, previous.values).map { Int($0) - Int($1) }
        let mean = diffs.reduce(0, +) / diffs.count
        let changed = diffs.filter { abs($0 - mean) > pixelDelta }.count
        return Double(changed) / Double(diffs.count)
    }
}
