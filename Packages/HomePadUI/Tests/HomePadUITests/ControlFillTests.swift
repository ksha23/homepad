import SwiftUI
import Testing
@testable import HomePadUI

/// The fill behind a control in a tile, worked out from the tile's surface.
struct ControlFillTests {
    private let minimum = ControlFill.minimumContrast

    @Test func aNearWhiteSurfaceGetsADarkerRowThatReachesTheContrast() {
        // Light glass on a white face, the frosted Home Screen and a white page.
        let surfaces = [
            GlassSurface.tone(over: BackdropTone(red: 0.91, green: 0.91, blue: 0.93), scheme: .light),
            GlassSurface.tone(over: BackdropTone(red: 0.85, green: 0.85, blue: 0.86), scheme: .light, isBackdropBlurred: true),
            GlassSurface.tone(over: .white, scheme: .light),
        ]
        for surface in surfaces {
            #expect(surface.luminance > 0.8)
            let fill = ControlFill(on: surface)
            #expect(!fill.isLighter)
            #expect(fill.contrast(on: surface) >= minimum - 1e-9)
            // The white row these tiles had could not stand out.
            #expect(ControlFill(isLighter: true, opacity: 0.35).contrast(on: surface) < 1.1)
        }
    }

    @Test func aDarkSurfaceKeepsTheLighterRowItHad() {
        // Dark glass on black, on a graphite face and on the blue Midnight face,
        // and on a dark frosted Home Screen.
        let surfaces = [
            GlassSurface.tone(over: .black, scheme: .dark),
            GlassSurface.tone(over: BackdropTone(red: 0.11, green: 0.11, blue: 0.12), scheme: .dark),
            GlassSurface.tone(over: BackdropTone(red: 0.2, green: 0.21, blue: 0.67), scheme: .dark),
            GlassSurface.tone(over: BackdropTone(red: 0.12, green: 0.12, blue: 0.13), scheme: .dark, isBackdropBlurred: true),
        ]
        for surface in surfaces {
            let fill = ControlFill(on: surface)
            #expect(fill == ControlFill(isLighter: true, opacity: ControlFill.faintest))
            #expect(fill.contrast(on: surface) >= minimum)
        }
    }

    @Test func everyBackdropGetsJustEnough() {
        for scheme in [ColorScheme.light, .dark] {
            for isBlurred in [false, true] {
                for step in 0...20 {
                    let backdrop = BackdropTone(luminance: Double(step) / 20)
                    let surface = GlassSurface.tone(over: backdrop, scheme: scheme, isBackdropBlurred: isBlurred)
                    let fill = ControlFill(on: surface)
                    let contrast = fill.contrast(on: surface)
                    #expect(contrast >= minimum - 1e-9)
                    // Only the faintest fill may go past the minimum, never a stronger one.
                    if fill.opacity > ControlFill.faintest {
                        #expect(contrast < minimum + 0.01)
                    }
                }
            }
        }
    }

    @Test func darkGlassOverABrightFaceGetsADarkerRow() {
        // In Dark, glass over a white face is middle gray, where a darker row
        // also gives its white text more contrast.
        let surface = GlassSurface.tone(over: BackdropTone(red: 0.91, green: 0.91, blue: 0.93), scheme: .dark)
        #expect(surface.luminance > BackdropTone.midpoint)
        let fill = ControlFill(on: surface)
        #expect(!fill.isLighter)
        #expect(fill.tone(over: surface).whiteTextContrast > surface.whiteTextContrast)
    }
}
