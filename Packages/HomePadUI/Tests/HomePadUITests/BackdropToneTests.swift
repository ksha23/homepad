import SwiftUI
import Testing
@testable import HomePadUI

/// How bright a backdrop is, and which look glass takes on it.
struct BackdropToneTests {
    @Test func theMidpointIsWhereBlackAndWhiteTextReadEqually() {
        let midpoint = BackdropTone.midpoint
        let onWhite = 1.05 / (midpoint + 0.05)
        let onBlack = (midpoint + 0.05) / 0.05
        #expect(abs(onWhite - onBlack) < 0.001)
        #expect(abs(midpoint - 0.179) < 0.001)
    }

    @Test func darkBackdropsGetDarkGlassAndBrightOnesLight() {
        #expect(BackdropTone.black.scheme() == .dark)
        #expect(BackdropTone(red: 0.12, green: 0.12, blue: 0.14).scheme() == .dark)
        #expect(BackdropTone(red: 0.93, green: 0.92, blue: 0.9).scheme() == .light)
        #expect(BackdropTone.white.scheme() == .light)
    }

    @Test func aToneNearTheMidpointKeepsTheLookGlassHas() {
        let justAbove = BackdropTone(luminance: BackdropTone.midpoint + 0.02)
        let justBelow = BackdropTone(luminance: BackdropTone.midpoint - 0.02)
        #expect(justAbove.scheme(keeping: .dark) == .dark)
        #expect(justBelow.scheme(keeping: .light) == .light)
        #expect(justAbove.scheme() == .light)
        #expect(justBelow.scheme() == .dark)
        // Well past the band, it turns.
        #expect(BackdropTone(luminance: BackdropTone.midpoint + 0.06).scheme(keeping: .dark) == .light)
        #expect(BackdropTone(luminance: BackdropTone.midpoint - 0.06).scheme(keeping: .light) == .dark)
    }

    @Test func whiteTextGetsJustEnoughShadeOnBrightBackdropsAndNoneOnDarkOnes() {
        // Dark backdrops keep white text as it is.
        #expect(BackdropTone.whiteTextShade(red: 0, green: 0, blue: 0, contrast: 3) == 0)
        #expect(BackdropTone.whiteTextShade(red: 0.15, green: 0.2, blue: 0.3, contrast: 3) == 0)

        // A bright one gets the lightest shade that reaches the contrast.
        let (red, green, blue) = (0.84, 0.88, 0.92)
        #expect(BackdropTone(red: red, green: green, blue: blue).whiteTextContrast < 3)
        let shade = BackdropTone.whiteTextShade(red: red, green: green, blue: blue, contrast: 3)
        let shaded = BackdropTone(red: red, green: green, blue: blue, opacity: 1 - shade)
        #expect(shaded.whiteTextContrast >= 3)
        #expect(shaded.whiteTextContrast < 3.01)

        // A higher contrast needs a deeper shade, and white needs the deepest.
        #expect(BackdropTone.whiteTextShade(red: red, green: green, blue: blue, contrast: 4.5) > shade)
        #expect(BackdropTone.whiteTextShade(red: 1, green: 1, blue: 1, contrast: 3)
            > BackdropTone.whiteTextShade(red: red, green: green, blue: blue, contrast: 3))
    }

    @Test func gradientsAndScrimsAverageAndDarken() {
        // The ends of a gradient count half.
        let gradient = BackdropTone.gradient([.black, .white, .black])
        #expect(abs(gradient.luminance - 0.5) < 0.001)
        #expect(BackdropTone.white.dimmed(by: 0.25).luminance < 1)
        #expect(BackdropTone.white.dimmed(by: 1).luminance == 0)
        // A see-through color is drawn over black.
        #expect(BackdropTone(red: 1, green: 1, blue: 1, opacity: 0).luminance == 0)
    }
}
