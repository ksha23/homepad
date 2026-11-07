import Foundation
import Testing
@testable import HomePadFaces

/// The shade the Weather face lays between its sky and its white text: just
/// enough on a bright sky, none on a dark one.
struct SkyShadeTests {
    private let minimum = FaceColorChoice.minimumContrast
    /// A portrait and a landscape iPad, width over height.
    private let aspectRatios = [0.75, 4.0 / 3]
    private let stops = 21

    private func height(_ index: Int) -> Double { Double(index) / Double(stops - 1) }

    @Test func whiteReadsOnEverySkyWithItsShade() {
        for condition in SkyCondition.allCases {
            for time in SkyTime.allCases {
                for aspectRatio in aspectRatios {
                    let shade = SkyPalette.textShade(condition, time, aspectRatio: aspectRatio, stops: stops)
                    for (index, opacity) in shade.enumerated() {
                        let sky = SkyPalette.brightest(condition, time, at: height(index), aspectRatio: aspectRatio)
                        let shaded = sky.mixed(with: .black, by: opacity)
                        #expect(shaded.contrast(with: .white) >= minimum - 0.001,
                                "\(time) \(condition) at \(height(index))")
                    }
                }
            }
        }
    }

    @Test func aBrightSkyGetsAShadeWhereItsTextSits() {
        // A snowy day is the brightest sky: white fails on its gradient alone,
        // at the bottom where the hourly forecast sits.
        let bottom = FaceRGB(hex: SkyPalette.colors(.snow, .day).bottom)
        #expect(bottom.contrast(with: .white) < minimum)
        let shade = SkyPalette.textShade(.snow, .day, aspectRatio: 0.75, stops: stops)
        #expect(shade.last ?? 0 > 0)
        // Its white clouds, where the place and the time sit, need a shade too.
        #expect(shade[2] > 0)
        // Just enough: the bottom reads at about the minimum, not darker.
        let shaded = bottom.mixed(with: .black, by: shade.last ?? 0)
        #expect(shaded.contrast(with: .white) < minimum + 0.01)
    }

    @Test func aDarkSkyKeepsWhiteWithNoShade() {
        for condition in SkyCondition.allCases {
            #expect(SkyPalette.textShade(condition, .night, aspectRatio: 0.75).allSatisfy { $0 == 0 }, "\(condition)")
        }
        #expect(SkyPalette.textShade(.thunder, .day, aspectRatio: 4.0 / 3).allSatisfy { $0 == 0 })
        #expect(SkyPalette.textShade(.rain, .day, aspectRatio: 4.0 / 3).allSatisfy { $0 == 0 })
    }

    @Test func cloudsCountOnlyAtTheHeightsTheyDriftAcross() {
        // Fog lies low, so its top is the plain gradient and its bottom is under cloud.
        let colors = SkyPalette.colors(.fog, .day)
        let top = FaceRGB(hex: colors.top)
        let gradientLow = top.mixed(with: FaceRGB(hex: colors.bottom), by: 0.7)
        #expect(SkyPalette.brightest(.fog, .day, at: 0, aspectRatio: 0.75) == top)
        #expect(SkyPalette.brightest(.fog, .day, at: 0.7, aspectRatio: 0.75).luminance > gradientLow.luminance)
    }
}
