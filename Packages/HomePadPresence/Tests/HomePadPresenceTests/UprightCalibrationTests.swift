import Foundation
import ImageIO
import Testing
@testable import HomePadPresence

/// Frames stand upright by what the faces in them say, whatever the rotation coordinator said.
@Suite struct UprightCalibrationTests {
    private func calibration() -> UprightCalibration {
        UprightCalibration(defaults: UserDefaults(suiteName: "presence.upright.\(UUID())"))
    }

    /// On the 11-inch the coordinator said upside down, and faces then read -122 to -170 degrees.
    @Test func upsideDownFacesTurnTheFramesHalfway() {
        var upright = calibration()
        #expect(upright.corrected(.down, backend: .faceTracking) == .down)
        var line: String?
        for roll in [-165.0, -122, -168, -170, -132] {
            line = upright.note(rollDegrees: roll, backend: .faceTracking, base: .down)
        }
        #expect(line != nil)
        #expect(upright.corrected(.down, backend: .faceTracking) == .up)
        // Other backends and orientations keep their own.
        #expect(upright.corrected(.down, backend: .depthScan) == .down)
        #expect(upright.corrected(.right, backend: .faceTracking) == .right)
    }

    @Test func uprightOrMixedFacesChangeNothing() {
        var upright = calibration()
        for roll in [5.0, -10, 3, 0, 12] { _ = upright.note(rollDegrees: roll, backend: .faceTracking, base: .down) }
        #expect(upright.corrected(.down, backend: .faceTracking) == .down)
        for roll in [170.0, 5, 175, -10, 178] { _ = upright.note(rollDegrees: roll, backend: .faceTracking, base: .down) }
        #expect(upright.corrected(.down, backend: .faceTracking) == .down)
    }

    @Test func quarterTurns() {
        #expect(UprightCalibration.quarter(of: 0) == 0)
        #expect(UprightCalibration.quarter(of: 90) == 1)
        #expect(UprightCalibration.quarter(of: -170) == 2)
        #expect(UprightCalibration.quarter(of: -90) == 3)
        #expect(UprightCalibration.quarter(of: -150) == 2)
        #expect(UprightCalibration.turned(.down, quarters: 2) == .up)
        #expect(UprightCalibration.turned(.up, quarters: 1) == .right)
    }
}
