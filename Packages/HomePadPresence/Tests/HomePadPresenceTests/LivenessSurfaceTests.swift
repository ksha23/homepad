import CoreGraphics
import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// Relief is measured on the face's own surface only. The 11-inch's traces
/// showed faces facing the iPad passing on the wall behind them (relief up to
/// 1.3 m), and turned faces reading 9 to 15 mm against the 12 mm cutoff.
@Suite struct LivenessSurfaceTests {
    /// A 9 by 9 grid, `depth(x, y)` with x and y from -0.5 to 0.5.
    private func grid(_ depth: (Double, Double) -> Double) -> [Float] {
        (0..<81).map { index in
            let x = Double(index % 9) / 8 - 0.5
            let y = Double(index / 9) / 8 - 0.5
            return Float(depth(x, y))
        }
    }

    /// A photo 0.6 m away, tilted, with a wall 2.5 m away beside it. Read as a
    /// whole the grid had two meters of relief and passed.
    @Test func aPhotoInFrontOfAFarWallIsFlat() {
        let photo = grid { x, y in x < 0.05 ? 0.6 + 0.05 * x + 0.02 * y : 2.5 }
        let result = DepthLiveness.evaluate(samples: photo, columns: 9)
        #expect(result.isLive == false)
        #expect(result.unsure == nil)
        #expect(result.reliefMeters < 0.002)
        #expect(abs((result.distanceMeters ?? 0) - 0.6) < 0.03)
    }

    /// When the photo covers less of the grid than the wall, the wall is the surface, and it is flat too.
    @Test func aSmallPhotoBeforeAWallIsStillFlat() {
        let photo = grid { x, _ in x < -0.3 ? 0.6 : 2.5 + 0.01 * x }
        let result = DepthLiveness.evaluate(samples: photo, columns: 9)
        #expect(result.isLive == false)
        #expect(result.reliefMeters < 0.002)
    }

    /// A face facing the iPad, with the wall behind it on part of the grid:
    /// live, on the face's own relief, not the wall's.
    @Test func aFrontalFaceIsLiveOnItsOwnRelief() {
        let face = grid { x, y in x > 0.3 ? 2.5 : 0.6 + 0.08 * (x * x + y * y) }
        let result = DepthLiveness.evaluate(samples: face, columns: 9)
        #expect(result.isLive)
        #expect(result.reliefMeters < 0.04)
        #expect(result.faceFraction > 0.7 && result.faceFraction < 0.8)
    }

    /// The side of a turned head: steep, gently curved, with the wall beside it. It reads flat.
    @Test func aProfileFaceReadsFlatOnItsOwnSurface() {
        let profile = grid { x, y in x < -0.3 ? 3.0 : 0.65 + 0.08 * x + 0.03 * x * x + 0.01 * y * y }
        let result = DepthLiveness.evaluate(samples: profile, columns: 9)
        #expect(result.isLive == false)
        #expect(result.reliefMeters < DepthLiveness.minimumReliefMeters)
        #expect(abs((result.distanceMeters ?? 0) - 0.66) < 0.03)
    }

    /// No one surface covers enough of the grid: the check cannot say, so it never votes.
    @Test func aGridOnNoOneSurfaceIsUnsure() {
        let scattered = grid { x, _ in x < -0.2 ? 0.6 : (x < 0.2 ? 1.2 : 2.4) }
        let result = DepthLiveness.evaluate(samples: scattered, columns: 9)
        #expect(result.isLive == false)
        #expect(result.unsure == .noSurface)
    }
}

/// A turned face that reads flat is unsure, so it is skipped. Facing the iPad, flat is a spoof.
@Suite struct TurnedFaceLivenessTests {
    /// A flat 9 by 9 surface across the middle of a 640x480 depth map, 0.6 m away.
    private func flatMap() -> DepthMap {
        DepthMap(width: 640, height: 480, meters: [Float](repeating: 0.6, count: 640 * 480))
    }

    private func frame() throws -> SensorFrame {
        let buffer = try #require(FaceEmbedder.blankFrame(width: 1280, height: 720))
        return SensorFrame(pixelBuffer: buffer, orientation: .up, timestamp: 0, source: .trueDepth)
    }

    private let box = CGRect(x: 0.4, y: 0.4, width: 0.12, height: 0.2)

    @Test func flatAndTurnedIsUnsure() throws {
        let result = DepthLiveness.evaluate(faceBox: box, in: try frame(), depth: flatMap(), yaw: 70 * .pi / 180)
        #expect(result.isLive == false)
        #expect(result.unsure == .turned(degrees: 70))
    }

    @Test func flatAndFacingTheIPadIsASpoof() throws {
        let result = DepthLiveness.evaluate(faceBox: box, in: try frame(), depth: flatMap(), yaw: 10 * .pi / 180)
        #expect(result.isLive == false)
        #expect(result.unsure == nil)
    }
}

/// An unsure sample neither matches nor counts as a spoof, and it ends the
/// cover a passed check gives samples without depth.
@MainActor @Suite struct UnsureSampleTests {
    @Test func anUnsureSampleIsSkipped() throws {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "presence.unsure.\(UUID())")!))
        services.settings[CoreSettings.faceRecognitionEnabled] = true
        let service = FaceRecognitionService(services: services, store: nil)
        let alice = UUID()
        try service.saveEnrollment(memberID: alice, embeddings: [LearningVectors.axis(0)])
        let turned = LivenessResult(isLive: false, reliefMeters: 0.008, validFraction: 1, unsure: .turned(degrees: 70))
        let sample = LearningVectors.sample(LearningVectors.probe(0.95, toward: 3), track: UUID(), liveness: turned)
        service.consider(sample, requireLiveness: true)
        #expect(service.lastDecision == nil)
    }
}
