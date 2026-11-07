import CoreVideo
import Foundation

/// A small grayscale grid made from a camera frame. Motion detection works on
/// this instead of full frames, which keeps it cheap and smooths sensor noise.
struct LumaFrame: Equatable, Sendable {
    let width: Int
    let height: Int
    /// Row-major luma, 0...255.
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must match the grid")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A uniform frame, handy for tests.
    init(width: Int, height: Int, value: UInt8) {
        self.init(width: width, height: height, pixels: Array(repeating: value, count: width * height))
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Averages blocks of a 32BGRA buffer into a `width` x `height` grid.
    /// Samples every fourth pixel inside each block, which is plenty for motion.
    init?(bgra pixelBuffer: CVPixelBuffer, width: Int = 96, height: Int = 54) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let blockWidth = max(1, sourceWidth / width)
        let blockHeight = max(1, sourceHeight / height)
        let step = 4
        var output = [UInt8](repeating: 0, count: width * height)
        for gridY in 0..<height {
            for gridX in 0..<width {
                var sum = 0
                var count = 0
                var y = gridY * blockHeight
                while y < min(sourceHeight, (gridY + 1) * blockHeight) {
                    var x = gridX * blockWidth
                    let row = bytes + y * bytesPerRow
                    while x < min(sourceWidth, (gridX + 1) * blockWidth) {
                        let pixel = row + x * 4
                        // BGRA, Rec. 601 luma weights in integer form.
                        sum += (29 * Int(pixel[0]) + 150 * Int(pixel[1]) + 77 * Int(pixel[2])) >> 8
                        count += 1
                        x += step
                    }
                    y += step
                }
                output[gridY * width + gridX] = UInt8(clamping: count > 0 ? sum / count : 0)
            }
        }
        self.init(width: width, height: height, pixels: output)
    }
}
