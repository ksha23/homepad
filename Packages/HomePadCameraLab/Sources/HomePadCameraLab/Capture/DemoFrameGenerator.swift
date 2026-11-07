import CoreGraphics
import CoreVideo
import UIKit

/// A synthetic camera for the simulator, which has no cameras. It draws a calm
/// room with a window, and every few seconds a figure walks across, so motion
/// detection, the MJPEG server, timelapse and Ask About This can all be exercised.
/// Every frame is labeled "Demo Feed" so it is never mistaken for a real camera.
@MainActor
final class DemoFrameGenerator: FrameProducer {
    let hub = FrameHub()
    let isDemo = true
    private(set) var position: CameraPosition?
    var onStatusChange: ((FeedStatus) -> Void)?

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "cameralab.demo")
    nonisolated static let size = CGSize(width: 1280, height: 720)
    nonisolated private static let framesPerSecond = 8.0

    func start(position: CameraPosition) {
        self.position = position
        guard timer == nil else { return }
        let hub = hub
        let start = Date()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1 / Self.framesPerSecond)
        timer.setEventHandler {
            let elapsed = Date().timeIntervalSince(start)
            if let buffer = Self.render(elapsed: elapsed, position: position) {
                hub.deliver(CameraFrame(pixelBuffer: buffer, capturedAt: Date(), isDemo: true))
            }
        }
        timer.resume()
        self.timer = timer
        onStatusChange?(.running)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        position = nil
        hub.reset()
        onStatusChange?(.stopped)
    }

    /// Draws one frame. A figure crosses the room for 4 s out of every 12 s.
    nonisolated static func render(elapsed: TimeInterval, position: CameraPosition) -> CVPixelBuffer? {
        let width = Int(size.width), height = Int(size.height)
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Flip to UIKit coordinates so text draws upright.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        drawScene(in: CGRect(x: 0, y: 0, width: width, height: height), elapsed: elapsed, position: position)
        return buffer
    }

    private nonisolated static func drawScene(in rect: CGRect, elapsed: TimeInterval, position: CameraPosition) {
        // Wall and floor.
        UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1).setFill()
        UIRectFill(rect)
        UIColor(red: 0.24, green: 0.20, blue: 0.17, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: rect.height * 0.72, width: rect.width, height: rect.height * 0.28))
        // Window with a slowly changing sky.
        let sky = 0.35 + 0.15 * sin(elapsed / 30)
        UIColor(red: 0.30 * sky, green: 0.55 * sky, blue: 0.95 * sky, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.width * 0.62, y: rect.height * 0.14, width: rect.width * 0.26, height: rect.height * 0.34), cornerRadius: 8).fill()
        // A plant.
        UIColor(red: 0.20, green: 0.55, blue: 0.30, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: rect.width * 0.12, y: rect.height * 0.46, width: 120, height: 150)).fill()
        UIColor(red: 0.55, green: 0.35, blue: 0.25, alpha: 1).setFill()
        UIRectFill(CGRect(x: rect.width * 0.12 + 30, y: rect.height * 0.60, width: 60, height: 70))
        // The walking figure.
        let cycle = elapsed.truncatingRemainder(dividingBy: 12)
        if cycle < 4 {
            let progress = cycle / 4
            let x = rect.width * (0.05 + 0.85 * progress)
            UIColor(white: 0.85, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: x, y: rect.height * 0.34, width: 54, height: 54)).fill()
            UIBezierPath(roundedRect: CGRect(x: x - 14, y: rect.height * 0.34 + 60, width: 82, height: 190), cornerRadius: 30).fill()
        }
        // Label and clock.
        let label = "DEMO FEED  \(position.title.uppercased())  \(Date().formatted(date: .omitted, time: .standard))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: CGPoint(x: rect.width - size.width - 32, y: rect.height - size.height - 24), withAttributes: attributes)
    }
}
