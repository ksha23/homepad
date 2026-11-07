import Foundation
import Testing
@testable import HomePadAudio

@Suite struct NoiseGeneratorTests {
    static let sampleCount = 96_000  // two seconds at 48 kHz

    static func samples(_ sound: AmbientSound, seed: UInt32 = 42) -> [Float] {
        var generator = NoiseGenerator(seed: seed)
        return (0..<sampleCount).map { _ in generator.next(sound) }
    }

    static func mean(_ x: [Float]) -> Double { x.reduce(0) { $0 + Double($1) } / Double(x.count) }
    static func rms(_ x: [Float]) -> Double { sqrt(x.reduce(0) { $0 + Double($1 * $1) } / Double(x.count)) }

    /// Lag-1 autocorrelation: about 0 for white noise, close to 1 for brown noise.
    static func lagOneCorrelation(_ x: [Float]) -> Double {
        let m = mean(x)
        var numerator = 0.0
        var denominator = 0.0
        for i in x.indices {
            let d = Double(x[i]) - m
            denominator += d * d
            if i > 0 { numerator += d * (Double(x[i - 1]) - m) }
        }
        return numerator / denominator
    }

    @Test func whiteNoiseIsUniformAndUncorrelated() {
        var generator = NoiseGenerator(seed: 7)
        let raw = (0..<Self.sampleCount).map { _ in generator.white() }
        #expect(raw.allSatisfy { $0 >= -1 && $0 <= 1 })
        #expect(abs(Self.mean(raw)) < 0.01)
        // Uniform on -1...1 has RMS 1 / sqrt(3).
        #expect(abs(Self.rms(raw) - 1 / sqrt(3)) < 0.01)
        #expect(abs(Self.lagOneCorrelation(raw)) < 0.02)
    }

    @Test(arguments: AmbientSound.allCases)
    func everySoundIsBoundedAndComfortablyLoud(_ sound: AmbientSound) {
        let x = Self.samples(sound)
        #expect(x.allSatisfy { $0 >= -1 && $0 <= 1 && $0.isFinite })
        let level = Self.rms(x)
        #expect(level > 0.1 && level < 0.35, "RMS \(level) for \(sound)")
        #expect(abs(Self.mean(x)) < 0.1)
    }

    @Test func spectrumDarkensFromWhiteToPinkToBrown() {
        let white = Self.lagOneCorrelation(Self.samples(.white))
        let pink = Self.lagOneCorrelation(Self.samples(.pink))
        let brown = Self.lagOneCorrelation(Self.samples(.brown))
        #expect(abs(white) < 0.02)
        #expect(pink > 0.5 && pink < 0.95)
        #expect(brown > 0.95)
        #expect(white < pink && pink < brown)
    }

    @Test func rainHasDropTransients() {
        // Crest factor (peak over RMS) is higher for rain than for its pink bed.
        func crest(_ x: [Float]) -> Double { Double(x.map(abs).max() ?? 0) / Self.rms(x) }
        #expect(crest(Self.samples(.rain)) > crest(Self.samples(.pink)))
    }

    @Test func sameSeedSameSound() {
        #expect(Self.samples(.rain, seed: 99).prefix(1000) == Self.samples(.rain, seed: 99).prefix(1000))
        #expect(Self.samples(.white, seed: 1).prefix(100) != Self.samples(.white, seed: 2).prefix(100))
    }

    @Test func gainRampGlidesWithoutJumping() {
        var ramp = GainRamp(initial: 0, target: 1, coefficient: 0.001)
        var previous: Float = 0
        for _ in 0..<10_000 {
            let value = ramp.next()
            #expect(value >= previous && value - previous <= 0.001 + .ulpOfOne)
            previous = value
        }
        #expect(previous > 0.99)
    }

    @Test func sleepTimerFadesWithEqualPowerCurve() {
        #expect(SleepTimer.fadeLevel(remaining: 600) == 1)
        #expect(SleepTimer.fadeLevel(remaining: 30, fadeDuration: 30) == 1)
        #expect(abs(SleepTimer.fadeLevel(remaining: 15, fadeDuration: 30) - sin(.pi / 4)) < 1e-9)
        #expect(SleepTimer.fadeLevel(remaining: 0) == 0)
        #expect(SleepTimer.fadeLevel(remaining: -5) == 0)
        #expect(SleepTimer.label(minutes: 0) == "Off")
        #expect(SleepTimer.label(minutes: 45) == "45 min")
    }

    @Test func defaultPresetsExist() {
        #expect(SleepPreset.defaultIDs.allSatisfy { SleepPreset.preset($0) != nil })
        #expect(Set(SleepPreset.all.map(\.id)).count == SleepPreset.all.count)
    }
}
