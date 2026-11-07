import Foundation
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadFaces

/// How a face's background, text and accent choices resolve to the colors it
/// draws, and the rule that keeps every combination readable.
@MainActor @Suite struct FaceColorTests {
    private let minimum = FaceColorChoice.minimumContrast

    // MARK: Contrast math

    @Test func contrastFollowsWCAG() {
        #expect(abs(FaceRGB.black.contrast(with: .white) - 21) < 0.001)
        #expect(FaceRGB.white.contrast(with: .white) == 1)
        #expect(FaceRGB(hex: "#FFFFFF") == .white)
        #expect(FaceRGB(hex: "000000") == .black)
        // Same fallback as Color(hex:).
        #expect(FaceRGB(hex: "nope") == FaceRGB(red: 0.5, green: 0.5, blue: 0.5))
        // Mid gray against white, a well known value.
        #expect(abs(FaceRGB(hex: "#767676").contrast(with: .white) - 4.54) < 0.01)
    }

    // MARK: Saved faces look the same

    @Test func untouchedFacesKeepTheirPresetColors() {
        for background in FaceColor.allCases {
            let preset = background.preset
            let colors = FaceColorSet(FaceColorChoice(background: background))
            #expect(colors.top == preset.top, "\(background)")
            #expect(colors.bottom == preset.bottom, "\(background)")
            #expect(colors.ink == preset.ink, "\(background)")
            #expect(colors.secondary == preset.secondary, "\(background)")
            #expect(colors.accent == preset.accent, "\(background)")
            #expect(colors.tile == preset.tile, "\(background)")
            #expect(colors.highlight == preset.tile, "\(background)")
            #expect(colors.onHighlight == (preset.isLight ? preset.ink : preset.bottom), "\(background)")
            #expect(colors.isLight == preset.isLight, "\(background)")
            #expect(!colors.hasChosenText && !colors.hasChosenAccent, "\(background)")
        }
    }

    @Test func facesSavedBeforeTheNewKeysAreAutomatic() {
        let saved = FaceConfiguration(faceID: "faces.modular", values: ["style": "digital", "color": "sage"])
        #expect(saved.colors(ModularFace.color) == FaceColorChoice(background: .sage))
        // No color saved at all: the face's own default.
        #expect(FaceConfiguration(faceID: "faces.modular").colors(ModularFace.color) == FaceColorChoice(background: .ocean))
        #expect(FaceConfiguration(faceID: "faces.numerals").colors(NumeralsFace.color).background == .green)
    }

    @Test func savedBackgroundValuesStillLoad() {
        // Saved names never change. New backgrounds would be added at the end.
        #expect(FaceColor.allCases.map(\.rawValue)
            == ["porcelain", "graphite", "lavender", "midnight", "ocean", "sage", "green", "coral", "sand", "rose"])
        #expect(FaceColorChoice.textKey == "textColor")
        #expect(FaceColorChoice.accentKey == "accentColor")
    }

    // MARK: Resolving choices

    @Test func chosenTextAndAccentResolve() {
        let face = FaceConfiguration(faceID: "faces.modular", values: ["color": "graphite", "textColor": "cream", "accentColor": "pink"])
        let choice = face.colors(ModularFace.color)
        #expect(choice == FaceColorChoice(background: .graphite, text: .cream, accent: FaceAccent(id: "pink")))
        let colors = FaceColorSet(choice)
        #expect(colors.ink == FaceTextColor.cream.rgb)
        #expect(colors.hasChosenText && colors.hasChosenAccent)
        // Pink already reads on Graphite, so it is drawn as it is.
        #expect(colors.accent == FaceAccent(id: "pink")?.rgb)
        #expect(colors.highlight == FaceAccent(id: "pink")?.rgb)
        // Secondary text sits between the text and the background.
        let middle = FaceColor.graphite.preset.middle
        #expect(colors.secondary.luminance < colors.ink.luminance)
        #expect(colors.secondary.luminance > middle.luminance)
    }

    @Test func unknownStoredColorsAreAutomatic() {
        let face = FaceConfiguration(faceID: "faces.digital", values: ["color": "ocean", "textColor": "gone", "accentColor": "chartreuse"])
        #expect(face.colors(DigitalFace.color) == FaceColorChoice(background: .ocean))
    }

    @Test func aFaceReadsOnlyThePartsItColors() {
        let values = ["color": "sand", "textColor": "navy", "accentColor": "pink"]
        let critters = FaceConfiguration(faceID: "faces.critters", values: values).colors(CrittersFace.color)
        #expect(critters == FaceColorChoice(background: .sand, text: .navy))
        let flow = FaceConfiguration(faceID: "faces.flow", values: ["color": "ocean", "textColor": "navy", "accentColor": "pink"])
        #expect(flow.colors(FlowFace.color) == FaceColorChoice(background: .ocean))
    }

    @Test func eachFaceOffersThePartsItDraws() {
        for option in [ModularFace.color, CalendarFace.color, AnalogFace.color,
                       NumeralsFace.color, DigitalFace.color, FadeFace.color] {
            #expect(option.colorRoles == .all)
        }
        // The Home face's accent fills the tiles that are on.
        #expect(HomeModularFace.color.colorRoles == [.text, .accent, .accentFillsTiles])
        #expect(CrittersFace.color.colorRoles == .text)
        #expect(FlowFace.color.colorRoles == [])
    }

    @Test func nightKeepsItsRedPaletteWhateverIsChosen() {
        let choice = FaceColorChoice(background: .porcelain, text: .navy, accent: FaceAccent(id: "yellow"))
        let palette = FacePalette.resolve(choice, condition: .night)
        #expect(palette.isNight)
        #expect(!palette.hasChosenText && !palette.hasChosenAccent)
        #expect(!FacePalette.resolve(choice, condition: .active).isNight)
    }

    @Test func atNightSecondaryTextIsTheSameRed() {
        // A dimmer red read at 1.7 to 1 against black. Night is one red.
        #expect(FacePalette.night.secondary == FacePalette.night.ink)
    }

    @Test func atNightTheFaceOnTheWallKeepsItsFarLayout() {
        for proximity in [ProximityLevel.far, .mid, .near] {
            #expect(HostedFace.shownProximity(proximity, condition: .night, isOnWall: true) == .far)
            // Previews keep both distances, and daytime follows the person.
            #expect(HostedFace.shownProximity(proximity, condition: .night, isOnWall: false) == proximity)
            #expect(HostedFace.shownProximity(proximity, condition: .ambient, isOnWall: true) == proximity)
        }
    }

    // MARK: Readability

    @Test func textTooCloseToTheBackgroundIsUnavailable() {
        #expect(!FaceColorChoice.isReadable(.white, on: .porcelain))
        #expect(FaceColorChoice.isReadable(.navy, on: .porcelain))
        #expect(FaceColorChoice.isReadable(.white, on: .graphite))
        #expect(!FaceColorChoice.isReadable(.navy, on: .graphite))
        // Chosen anyway (the background changed after), the face draws the
        // background's own text and keeps the choice for a background it reads on.
        let choice = FaceColorChoice(background: .porcelain, text: .white)
        #expect(choice.effectiveText == nil)
        #expect(FaceColorSet(choice).ink == FaceColor.porcelain.preset.ink)
        #expect(!FaceColorSet(choice).hasChosenText)
        #expect(FaceColorChoice(background: .graphite, text: .white).effectiveText == .white)
    }

    @Test func everyChosenTextThatShowsReads() {
        for background in FaceColor.allCases {
            for text in FaceTextColor.allCases {
                let colors = FaceColorSet(FaceColorChoice(background: background, text: text))
                guard colors.hasChosenText else { continue }
                #expect(FaceColorChoice.worstContrast(of: colors.ink, on: background.preset) >= minimum, "\(text) on \(background)")
            }
        }
    }

    @Test func everyBackgroundOffersSomeTextColorsAndEveryTextColorReadsSomewhere() {
        for background in FaceColor.allCases {
            let readable = FaceTextColor.allCases.filter { FaceColorChoice.isReadable($0, on: background) }
            #expect(readable.count >= 2, "\(background)")
        }
        for text in FaceTextColor.allCases {
            #expect(FaceColor.allCases.contains { FaceColorChoice.isReadable(text, on: $0) }, "\(text)")
        }
    }

    @Test func accentsDeepenOrLightenUntilTheyRead() {
        for background in FaceColor.allCases {
            for accent in FaceAccent.all {
                let shade = FaceColorChoice.shade(of: accent, on: background)
                #expect(FaceColorChoice.worstContrast(of: shade, on: background.preset) >= minimum - 0.01,
                        "\(accent.id) on \(background)")
            }
        }
        // Yellow deepens on a light background and stays as it is on a dark one.
        let yellow = FaceAccent(id: "yellow")!
        #expect(FaceColorChoice.shade(of: yellow, on: .porcelain).luminance < yellow.rgb.luminance)
        #expect(FaceColorChoice.shade(of: yellow, on: .graphite) == yellow.rgb)
        // Blue lightens on Midnight, keeping more blue than red.
        let blue = FaceColorChoice.shade(of: FaceAccent(id: "blue")!, on: .midnight)
        #expect(blue.luminance > FaceAccent(id: "blue")!.rgb.luminance)
        #expect(blue.blue > blue.red)
    }

    @Test func homeTilesThatAreOnStayReadable() {
        for background in FaceColor.allCases {
            let accents: [FaceAccent?] = FaceAccent.all.map { $0 } + [nil]
            for accent in accents {
                for text in FaceTextColor.allCases {
                    let colors = FaceColorSet(FaceColorChoice(background: background, text: text, accent: accent))
                    guard colors.hasChosenText || colors.hasChosenAccent else { continue }
                    #expect(colors.onHighlight.contrast(with: colors.highlight) >= minimum,
                            "\(text) on \(accent?.id ?? "automatic") over \(background)")
                }
            }
        }
        // The chosen text is kept on the tile when it reads there.
        let navyOnYellow = FaceColorSet(FaceColorChoice(background: .porcelain, text: .navy, accent: FaceAccent(id: "yellow")))
        #expect(navyOnYellow.onHighlight == FaceTextColor.navy.rgb)
    }

    @Test func bubbleTextReadsOnWhite() {
        for background in FaceColor.allCases {
            let texts: [FaceTextColor?] = [nil] + FaceTextColor.allCases.map { $0 }
            for text in texts {
                let colors = FaceColorSet(FaceColorChoice(background: background, text: text))
                #expect(colors.inkOnWhite.contrast(with: .white) >= minimum, "\(text?.rawValue ?? "automatic") on \(background)")
            }
        }
    }

    // MARK: Keys and captions

    @Test func colorKeysDoNotClashWithAnyOption() {
        for definition in FaceCatalog.all {
            let ids = Set(definition.options.map(\.id))
            #expect(!ids.contains(FaceColorChoice.textKey), "\(definition.id)")
            #expect(!ids.contains(FaceColorChoice.accentKey), "\(definition.id)")
            for option in definition.options where option.colorRoles != [] {
                #expect(option.id == "color", "\(definition.id)")
            }
        }
    }

    @Test func captionsNameChosenColors() {
        #expect(FaceColorChoice(background: .ocean).caption == "Ocean")
        #expect(FaceColorChoice(background: .ocean, text: .navy, accent: FaceAccent(id: "pink")).caption
            == "Ocean, Navy Text, Pink Accent")
        // Text that cannot be read is not drawn, so it is not named either.
        #expect(FaceColorChoice(background: .ocean, text: .white).caption == "Ocean")
        let face = FaceConfiguration(faceID: "faces.digital", values: ["style": "thin", "color": "ocean", "accentColor": "pink"])
        #expect(DigitalFace.definition.caption(for: face) == "Thin, Ocean, Pink Accent")
    }

    @Test func photosTimeColorsKeepTheirOriginalChoices() {
        let ids = PhotosFace.tint.choices.map(\.id)
        #expect(Array(ids.prefix(2)) == ["photo", "white"])
        #expect(FaceTextColor(rawValue: "photo") == nil)
        for id in ids.dropFirst() {
            #expect(FaceTextColor.light.contains { $0.rawValue == id }, "\(id)")
        }
        #expect(FaceConfiguration(faceID: "faces.photos").value(PhotosFace.tint) == "photo")
    }

    // MARK: Backdrop tone

    /// Glass widgets take their look from the background's luminance, and
    /// that agrees with how each background was designed.
    @Test func paletteToneAgreesWithEachBackgroundsOwnLightness() {
        for background in FaceColor.allCases {
            let palette = FacePalette(FaceColorChoice(background: background))
            #expect((palette.tone.scheme() == .light) == background.preset.isLight, "\(background)")
        }
        #expect(FacePalette.night.tone.luminance == 0)
    }
}
