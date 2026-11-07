import HomePadCore
import Testing
@testable import HomePadShell

@Suite struct AutoBrightnessTests {
    @Test func curveRisesWithRoomLight() {
        let samples = [0.0, 1, 10, 100, 1_000, 10_000, 50_000].map(BrightnessLevels.autoBrightness(lux:))
        #expect(samples == samples.sorted())
        #expect(samples.first! >= 0.05 && samples.first! <= 0.1)
        #expect(abs(BrightnessLevels.autoBrightness(lux: 100) - 0.53) < 0.03)
        #expect(samples.last! == 1)
    }

    @Test func conditionsStayRelativeToActive() {
        let levels = BrightnessLevels.standard
        let active = levels.target(for: KioskState(condition: .active, isInteracting: true, isNight: false),
                                   ambientLight: .normal, ambientLux: 100, adaptToRoomLight: true)
        let ambient = levels.target(for: KioskState(condition: .ambient, isInteracting: false, isNight: false),
                                    ambientLight: .normal, ambientLux: 100, adaptToRoomLight: true)
        let darkRoom = levels.target(for: KioskState(condition: .active, isInteracting: true, isNight: false),
                                     ambientLight: .dark, ambientLux: 2, adaptToRoomLight: true)
        #expect(ambient < active)
        #expect(darkRoom < active)
        #expect(abs(ambient / active - levels.ambient / levels.active) < 0.01)
    }

    @Test func manualLevelsWhenAutoBrightnessIsOff() {
        let levels = BrightnessLevels.standard
        let value = levels.target(for: KioskState(condition: .active, isInteracting: true, isNight: false),
                                  ambientLight: .dark, ambientLux: 2, adaptToRoomLight: false)
        #expect(value == levels.active)
    }
}

@Suite struct FollowSystemBrightnessTests {
    private let levels = BrightnessLevels.standard

    @Test func dimsRelativeToTheSystemLevelAndNeverBrightens() {
        let dimmed = KioskBrightness.dimmedLevel(for: KioskState(condition: .dimmed, isInteracting: false, isNight: false),
                                                 base: 0.6, levels: levels)
        #expect(abs(dimmed - 0.6 * levels.dimmed / levels.active) < 0.011)
        let nightInDarkRoom = KioskBrightness.dimmedLevel(for: KioskState(condition: .night, isInteracting: true, isNight: true),
                                                          base: 0.08, levels: levels)
        #expect(nightInDarkRoom <= 0.08)
        #expect(KioskBrightness.dimmedLevel(for: KioskState(condition: .sleeping, isInteracting: false, isNight: false),
                                            base: 0.5, levels: levels) == 0)
    }
}
