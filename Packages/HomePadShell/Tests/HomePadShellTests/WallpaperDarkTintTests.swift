import HomePadUI
import SwiftUI
import Testing
@testable import HomePadShell

/// In Dark, a wallpaper brighter than `HomeWallpaperView.darkLimit` is tinted down to it.
@MainActor
@Suite struct WallpaperDarkTintTests {
    @Test func aBrightWallpaperIsTintedDownToTheLimitInDark() {
        for luminance in [0.15, 0.4, 0.9] {
            let tone = BackdropTone(luminance: luminance)
            let tint = HomeWallpaperView.darkTint(over: tone, scheme: .dark)
            #expect(tint > 0)
            #expect(abs(tone.dimmed(by: tint).luminance - HomeWallpaperView.darkLimit) < 0.000_1)
        }
    }

    @Test func aDarkWallpaperKeepsItsLook() {
        #expect(HomeWallpaperView.darkTint(over: BackdropTone(luminance: 0.05), scheme: .dark) == 0)
        #expect(HomeWallpaperView.darkTint(over: BackdropTone(luminance: HomeWallpaperView.darkLimit), scheme: .dark) == 0)
    }

    @Test func lightAndAnUnknownToneAreNotTinted() {
        #expect(HomeWallpaperView.darkTint(over: BackdropTone(luminance: 0.9), scheme: .light) == 0)
        #expect(HomeWallpaperView.darkTint(over: nil, scheme: .dark) == 0)
    }

    /// The tone glass reads includes the tint, so glass on a tinted wallpaper turns dark.
    @Test func glassOnATintedWallpaperTurnsDark() {
        let tone = HomeWallpaperView.tone(.photo, accent: .blue, hasPhoto: true, photoTone: .white, faceTone: nil, scheme: .dark)
        #expect(tone?.scheme() == .dark)
        let light = HomeWallpaperView.tone(.photo, accent: .blue, hasPhoto: true, photoTone: .white, faceTone: nil, scheme: .light)
        #expect(light?.scheme() == .light)
    }
}
