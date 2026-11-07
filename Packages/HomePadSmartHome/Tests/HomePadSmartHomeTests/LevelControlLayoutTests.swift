import CoreGraphics
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// The full-height level control of a light, a fan or a blind: its size on the
/// screen, and where the symbol and the value go as the level changes.
@Suite("Level control layout")
struct LevelControlLayoutTests {
    /// The room an accessory detail's control has on an 11-inch iPad in landscape.
    private let landscape11 = CGSize(width: 1080, height: 650)
    private let portrait11 = CGSize(width: 700, height: 1030)

    @Test func theControlIsFullHeightAndAtLeastHalfTheWidth() {
        for space in [landscape11, portrait11, CGSize(width: 1240, height: 840)] {
            let slider = DetailControlMetrics(space: space, proximity: .near).slider
            #expect(slider.height == space.height)
            #expect(slider.width >= space.width * 0.5)
            #expect(slider.width <= max(space.height, space.width * 0.5))
        }
    }

    @Test func theValueIsAboutAFifthOfTheScreenTall() {
        let slider = DetailControlMetrics(space: landscape11, proximity: .near).slider
        let layout = LevelControlLayout(size: slider, level: 0.7)
        // SF Rounded digits are about 0.7 of the font size. The screen is 834 points tall.
        let digits = layout.valueSize * 0.7
        #expect(digits / 834 > 0.16)
        #expect(digits / 834 < 0.22)
    }

    @Test func theSymbolRidesTheFillLine() {
        let size = CGSize(width: 650, height: 650)
        for level in [0.4, 0.55, 0.72, 0.85] {
            let layout = LevelControlLayout(size: size, level: level)
            let line = size.height - layout.fillHeight
            let symbolHeight = layout.symbolSize * 1.2
            #expect(abs(layout.symbolCenterY - line) < symbolHeight / 2, "The line crosses the symbol at \(level)")
        }
    }

    @Test func theValueSitsOnTheColorWhenItFitsAndAboveItWhenNot() {
        let size = CGSize(width: 650, height: 650)
        let high = LevelControlLayout(size: size, level: 0.72)
        #expect(high.valueIsOnFill)
        #expect(high.valueCenterY > high.symbolCenterY)
        #expect(high.valueCenterY > size.height - high.fillHeight, "Under the fill line")

        let low = LevelControlLayout(size: size, level: 0.2)
        #expect(!low.valueIsOnFill)
        #expect(low.valueCenterY < low.symbolCenterY)
        #expect(low.valueCenterY < size.height - low.fillHeight, "Above the fill line")
    }

    @Test(arguments: [0.0, 0.05, 0.5, 0.95, 1.0])
    func everythingStaysInside(level: Double) {
        let size = CGSize(width: 650, height: 650)
        let layout = LevelControlLayout(size: size, level: level)
        let padding = LevelControlLayout.padding
        let symbolHalf = layout.symbolSize * 0.6
        let valueHalf = layout.valueSize * 0.425
        #expect(layout.symbolCenterY - symbolHalf >= padding - 0.5)
        #expect(layout.symbolCenterY + symbolHalf <= size.height - padding + 0.5)
        #expect(layout.valueCenterY - valueHalf >= padding - 0.5)
        #expect(layout.valueCenterY + valueHalf <= size.height - padding + 0.5)
        // The symbol and the value never overlap.
        #expect(abs(layout.valueCenterY - layout.symbolCenterY) >= symbolHalf + valueHalf - 0.5)
    }
}
