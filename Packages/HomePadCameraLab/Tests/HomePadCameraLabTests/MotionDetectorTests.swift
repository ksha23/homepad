import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import HomePadCameraLab

@Suite struct MotionDetectorTests {
    private let width = 40
    private let height = 30

    /// A gray room with a bright square at (x, y).
    private func frame(background: UInt8 = 80, squareAt origin: (x: Int, y: Int)? = nil, size: Int = 6, squareValue: UInt8 = 220) -> LumaFrame {
        var frame = LumaFrame(width: width, height: height, value: background)
        if let origin {
            for y in origin.y..<min(height, origin.y + size) {
                for x in origin.x..<min(width, origin.x + size) { frame[x, y] = squareValue }
            }
        }
        return frame
    }

    private var medium: MotionDetector { MotionDetector(configuration: MotionSensitivity.medium.configuration) }

    @Test func firstFrameOnlySetsTheBackground() {
        var detector = medium
        #expect(detector.process(frame()) == .still)
        #expect(detector.background?.count == width * height)
    }

    @Test func identicalFramesAreStill() {
        var detector = medium
        for _ in 0..<10 {
            let result = detector.process(frame())
            #expect(!result.isMotion)
            #expect(result.changedFraction == 0)
        }
    }

    @Test func movingObjectIsMotionWithABoundingBox() throws {
        var detector = medium
        _ = detector.process(frame())
        let first = detector.process(frame(squareAt: (10, 10)))
        #expect(!first.isMotion, "one changed frame is not enough")
        let second = detector.process(frame(squareAt: (12, 10)))
        #expect(second.isMotion)
        #expect(second.changedFraction > MotionSensitivity.medium.configuration.minimumChangedFraction)
        // The square now covers columns 12...17 and rows 10...15.
        let box = try #require(second.boundingBox)
        #expect(abs(box.minX - 12.0 / Double(width)) < 0.001)
        #expect(abs(box.minY - 10.0 / Double(height)) < 0.001)
        #expect(abs(box.width - 6.0 / Double(width)) < 0.001)
        #expect(abs(box.height - 6.0 / Double(height)) < 0.001)
    }

    @Test func uniformBrightnessChangeIsNotMotion() {
        var detector = medium
        _ = detector.process(frame(background: 80))
        for level: UInt8 in [110, 140, 170] {
            let result = detector.process(frame(background: level))
            #expect(!result.isMotion)
            #expect(result.changedFraction == 0)
        }
    }

    @Test func sensorNoiseBelowThresholdIsIgnored() {
        var detector = medium
        _ = detector.process(frame())
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<20 {
            var noisy = frame()
            for index in noisy.pixels.indices {
                noisy.pixels[index] = UInt8(clamping: 80 + Int.random(in: -10...10, using: &generator))
            }
            #expect(!detector.process(noisy).isMotion)
        }
    }

    @Test func wholeSceneChangeRebasesInsteadOfAlarming() {
        var detector = medium
        _ = detector.process(frame())
        // A checkerboard replaces the flat wall: the camera was bumped.
        var bumped = frame()
        for y in 0..<height {
            for x in 0..<width where (x + y).isMultiple(of: 2) { bumped[x, y] = 250 }
            for x in 0..<width where !(x + y).isMultiple(of: 2) { bumped[x, y] = 0 }
        }
        let result = detector.process(bumped)
        #expect(result.isSceneChange)
        #expect(!result.isMotion)
        #expect(!detector.process(bumped).isMotion)
    }

    @Test func stationaryNewObjectFadesIntoTheBackground() {
        var detector = medium
        _ = detector.process(frame())
        var lastResult = MotionDetector.Result.still
        for _ in 0..<120 { lastResult = detector.process(frame(squareAt: (5, 5))) }
        #expect(!lastResult.isMotion)
    }

    @Test func sensitivityLevelsOrderSmallMotion() {
        // A 3 by 3 square of moderate contrast: only High should notice.
        func detect(_ sensitivity: MotionSensitivity) -> Bool {
            var detector = MotionDetector(configuration: sensitivity.configuration)
            _ = detector.process(frame())
            var detected = false
            for step in 0..<4 {
                detected = detector.process(frame(squareAt: (step * 3, 4), size: 3, squareValue: 105)).isMotion || detected
            }
            return detected
        }
        #expect(detect(.high))
        #expect(!detect(.medium))
        #expect(!detect(.low))
    }

    @Test func lumaFromBGRAPixelBuffer() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixelBuffer = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<48 {
            for x in 0..<64 {
                let pixel = base + y * bytesPerRow + x * 4
                let white = x >= 32
                pixel[0] = white ? 255 : 0; pixel[1] = white ? 255 : 0; pixel[2] = white ? 255 : 0; pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let luma = try #require(LumaFrame(bgra: pixelBuffer, width: 8, height: 6))
        #expect(luma[0, 0] == 0)
        #expect(luma[7, 5] >= 254)
        #expect(luma[3, 2] == 0)
        #expect(luma[4, 2] >= 254)
    }
}

/// Deterministic noise for tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
