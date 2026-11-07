import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

@Suite struct SoundDebounceTests {
    private let t0 = Date(timeIntervalSince1970: 4_000_000)

    @Test func sustainedSoundsNeedTwoHits() {
        var debouncer = SoundEventDebouncer(minimumConfidence: 0.6)
        #expect(debouncer.process(kind: .smokeAlarm, confidence: 0.9, at: t0) == nil)
        let alert = debouncer.process(kind: .smokeAlarm, confidence: 0.8, at: t0.addingTimeInterval(1))
        #expect(alert?.kind == .smokeAlarm)
        // The best confidence of the confirming hits is reported.
        #expect(alert?.confidence == 0.9)
    }

    @Test func hitsTooFarApartDoNotConfirm() {
        var debouncer = SoundEventDebouncer(minimumConfidence: 0.6)
        #expect(debouncer.process(kind: .babyCrying, confidence: 0.9, at: t0) == nil)
        #expect(debouncer.process(kind: .babyCrying, confidence: 0.9, at: t0.addingTimeInterval(10)) == nil)
    }

    @Test func sharpSoundsFireOnOneHit() {
        var debouncer = SoundEventDebouncer(minimumConfidence: 0.6)
        #expect(debouncer.process(kind: .glassBreaking, confidence: 0.7, at: t0)?.kind == .glassBreaking)
    }

    @Test func cooldownSuppressesRepeats() {
        var debouncer = SoundEventDebouncer(minimumConfidence: 0.6)
        #expect(debouncer.process(kind: .doorbell, confidence: 0.9, at: t0) != nil)
        #expect(debouncer.process(kind: .doorbell, confidence: 0.9, at: t0.addingTimeInterval(5)) == nil)
        let later = t0.addingTimeInterval(SoundAlertKind.doorbell.cooldown + 1)
        #expect(debouncer.process(kind: .doorbell, confidence: 0.9, at: later) != nil)
    }

    @Test func lowConfidenceAndDisabledKindsAreIgnored() {
        var debouncer = SoundEventDebouncer(minimumConfidence: 0.6, enabledKinds: [.doorbell])
        #expect(debouncer.process(kind: .doorbell, confidence: 0.5, at: t0) == nil)
        #expect(debouncer.process(kind: .knock, confidence: 0.95, at: t0) == nil)
    }

    @Test func classifierLabelsMapToKinds() {
        #expect(SoundAlertKind.kind(forClassifierLabel: "smoke_detector") == .smokeAlarm)
        #expect(SoundAlertKind.kind(forClassifierLabel: "police_siren") == .siren)
        #expect(SoundAlertKind.kind(forClassifierLabel: "door_bell") == .doorbell)
        #expect(SoundAlertKind.kind(forClassifierLabel: "accordion") == nil)
        #expect(SoundAlertKind.smokeAlarm.eventLabel == SoundEventLabel.smokeAlarm)
    }
}

@Suite struct MotionDetectionTests {
    private func grid(_ value: (Int) -> UInt8) -> LumaGrid {
        LumaGrid(columns: 8, rows: 8, values: (0..<64).map(value))
    }

    @Test func movingPatchIsMotion() {
        var detector = MotionDetector(pixelDelta: 15, areaFraction: 0.05)
        #expect(detector.process(grid { _ in 100 }) == false)
        // Eight of 64 cells get much brighter: someone walked in.
        let moved = detector.process(grid { $0 < 8 ? 180 : 100 })
        #expect(moved)
    }

    @Test func globalBrightnessChangeIsNotMotion() {
        let before = grid { _ in 100 }
        let after = grid { _ in 160 }
        #expect(MotionDetector.changedFraction(previous: before, current: after, pixelDelta: 15) == 0)
    }

    @Test func depthBlobAppearing() {
        let wall = [Float](repeating: 3.5, count: 100)
        var person = wall
        for i in 40..<50 { person[i] = 1.4 }
        let result = depthCompare(wall, person)
        #expect(result.moved)
        #expect(result.nearestMeters == Double(Float(1.4)))
        #expect(depthCompare(wall, wall).moved == false)
    }

    private func depthCompare(_ previous: [Float], _ current: [Float]) -> DepthMotionDetector.Result {
        DepthMotionDetector.compare(previous: previous, current: current, columns: 10, changeMeters: 0.15,
                                    noisePerSquareMeter: 0.03, maxRange: 4, areaFraction: 0.05)
    }

    @Test func scatteredDepthNoiseIsNotMotion() {
        let room = [Float](repeating: 2, count: 100)
        var noisy = room
        // Ten changed cells, but no two touching: noise, not a person.
        for i in stride(from: 0, to: 100, by: 11) { noisy[i] = 1.2 }
        let result = depthCompare(room, noisy)
        #expect(result.moved == false)
        #expect(result.blobFraction == 0.01)
    }

    @Test func farDepthMustChangeMoreToCount() {
        // A wall 3.5 m away jittering by 0.3 m is TrueDepth noise at that range.
        let wall = [Float](repeating: 3.5, count: 100)
        #expect(depthCompare(wall, wall.map { $0 - 0.3 }).moved == false)
        // The same change 1 m away is real.
        let near = [Float](repeating: 1, count: 100)
        #expect(depthCompare(near, near.map { $0 - 0.3 }).moved)
    }

    @Test func holesFillingFarAwayAreNotMotion() {
        let holes = [Float](repeating: .nan, count: 100)
        #expect(depthCompare(holes, [Float](repeating: 3, count: 100)).moved == false)
        #expect(depthCompare(holes, [Float](repeating: 1.5, count: 100)).moved)
    }

    @Test func launchArguments() {
        let options = PresenceLaunchOptions(arguments: ["app", "-HomePadSimulatePresence", "-HomePadOpenApp", "mirror"])
        #expect(options.simulation == .cycle)
        let held = PresenceLaunchOptions(arguments: ["app", "-HomePadSimulatePresence", "near", "-HomePadSimulateSound", "smoke_alarm"])
        #expect(held.simulation == .hold(.near))
        #expect(held.simulatedSound == .smokeAlarm)
        #expect(PresenceLaunchOptions(arguments: ["app"]).isSimulated == false)
    }
}
