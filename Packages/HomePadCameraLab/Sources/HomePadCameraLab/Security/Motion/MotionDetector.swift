import CoreGraphics
import Foundation

/// Frame differencing against a slowly adapting background.
///
/// For each grid cell it compares the new luma with the background, after
/// removing the frame-wide average change (so lights dimming or a cloud passing
/// do not count). Cells that differ by more than `pixelThreshold` are "changed".
/// Motion is reported when the changed fraction stays above
/// `minimumChangedFraction` for `requiredConsecutiveFrames` frames in a row.
/// A change over most of the frame (camera bumped, lights switched) re-bases
/// the background instead of alarming.
struct MotionDetector {
    struct Configuration: Equatable, Sendable {
        /// Luma difference (0...255) for a cell to count as changed.
        var pixelThreshold: Double
        /// Fraction of cells that must change to count as motion.
        var minimumChangedFraction: Double
        /// Above this fraction the whole scene changed, so re-base instead of alarming.
        var sceneChangeFraction: Double = 0.6
        /// How fast the background absorbs the current frame (0...1 per frame).
        var backgroundAdaptation: Double = 0.05
        /// Frames in a row above the threshold before motion is reported.
        var requiredConsecutiveFrames: Int = 2
    }

    struct Result: Equatable, Sendable {
        /// Fraction of cells that changed, 0...1.
        var changedFraction: Double
        /// Normalized box (origin top left, 0...1) around the changed cells.
        var boundingBox: CGRect?
        var isMotion: Bool
        var isSceneChange: Bool

        static let still = Result(changedFraction: 0, boundingBox: nil, isMotion: false, isSceneChange: false)
    }

    let configuration: Configuration
    private(set) var background: [Double]?
    private var consecutiveFrames = 0

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Feeds one frame and returns what changed since the background.
    mutating func process(_ frame: LumaFrame) -> Result {
        let count = frame.pixels.count
        guard var background, background.count == count, count > 0 else {
            self.background = frame.pixels.map(Double.init)
            consecutiveFrames = 0
            return .still
        }

        var meanDelta = 0.0
        for index in 0..<count { meanDelta += Double(frame.pixels[index]) - background[index] }
        meanDelta /= Double(count)

        var changed = 0
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                let index = y * frame.width + x
                let difference = abs(Double(frame.pixels[index]) - background[index] - meanDelta)
                guard difference > configuration.pixelThreshold else { continue }
                changed += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let fraction = Double(changed) / Double(count)

        if fraction >= configuration.sceneChangeFraction {
            self.background = frame.pixels.map(Double.init)
            consecutiveFrames = 0
            return Result(changedFraction: fraction, boundingBox: nil, isMotion: false, isSceneChange: true)
        }

        let rate = configuration.backgroundAdaptation
        for index in 0..<count {
            background[index] += rate * (Double(frame.pixels[index]) - background[index])
        }
        self.background = background

        consecutiveFrames = fraction >= configuration.minimumChangedFraction ? consecutiveFrames + 1 : 0
        let box: CGRect? = changed > 0 ? CGRect(
            x: Double(minX) / Double(frame.width), y: Double(minY) / Double(frame.height),
            width: Double(maxX - minX + 1) / Double(frame.width), height: Double(maxY - minY + 1) / Double(frame.height)
        ) : nil
        return Result(
            changedFraction: fraction, boundingBox: box,
            isMotion: consecutiveFrames >= configuration.requiredConsecutiveFrames, isSceneChange: false
        )
    }
}
