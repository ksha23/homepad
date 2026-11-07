import CoreVideo
import Vision

/// Confirms that motion came from a person, which cuts false alarms from
/// shadows, curtains and pets. Runs only on frames where motion was found.
enum HumanDetector {
    /// Normalized boxes (origin top left) around people in the frame.
    static func people(in pixelBuffer: CVPixelBuffer, minimumConfidence: Float = 0.4) async -> [CGRect] {
        var request = DetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        guard let observations = try? await request.perform(on: pixelBuffer) else { return [] }
        return observations
            .filter { $0.confidence >= minimumConfidence }
            .map { observation in
                // Vision uses a bottom-left origin.
                let box = observation.boundingBox.cgRect
                return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }
    }
}
