import HomePadCore
import HomePadUI
import SwiftUI

/// Resolved colors a face draws with. Night mode swaps every entry for the
/// dim red palette, whatever was chosen, so the screen never lights up a dark
/// bedroom.
struct FacePalette {
    var top: Color
    var bottom: Color
    var ink: Color
    var secondary: Color
    var accent: Color
    var tile: Color
    /// The fill of a Home face tile that is on, and the ink on it.
    var highlight: Color
    var onHighlight: Color
    /// Text on a white bubble, readable whatever the text color.
    var inkOnWhite: Color
    var isLight: Bool
    /// How bright the background is, for the glass widgets laid over it.
    var tone: BackdropTone
    var isNight = false
    /// True when the person picked the text color rather than the background's own.
    var hasChosenText = false
    /// True when the person picked the accent rather than the background's own.
    var hasChosenAccent = false

    init(_ colors: FaceColorSet) {
        top = colors.top.color
        bottom = colors.bottom.color
        ink = colors.ink.color
        secondary = colors.secondary.color
        accent = colors.accent.color
        tile = colors.tile.color
        highlight = colors.highlight.color
        onHighlight = colors.onHighlight.color
        inkOnWhite = colors.inkOnWhite.color
        isLight = colors.isLight
        tone = .gradient([colors.top.tone, colors.bottom.tone])
        hasChosenText = colors.hasChosenText
        hasChosenAccent = colors.hasChosenAccent
    }

    /// The daylight palette for a color choice.
    init(_ choice: FaceColorChoice) {
        self.init(FaceColorSet(choice))
    }

    private init(night: Void) {
        top = .black
        bottom = .black
        ink = Theme.nightRed.opacity(0.85)
        // One red, like HomeView's night face. A dimmer red for secondary
        // text read at 1.7 to 1 against black and vanished in a dark room.
        secondary = ink
        accent = Theme.nightRed
        tile = Theme.nightRed.opacity(0.14)
        highlight = tile
        onHighlight = ink
        inkOnWhite = .black
        isLight = false
        tone = .black
        isNight = true
    }

    /// The dim red night palette.
    static let night = FacePalette(night: ())

    var background: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// The palette to draw with for a color choice under a display condition.
    static func resolve(_ choice: FaceColorChoice, condition: DisplayCondition) -> FacePalette {
        condition == .night ? .night : FacePalette(choice)
    }

    /// The palette for a background with its own text and accent.
    static func resolve(_ color: FaceColor, condition: DisplayCondition) -> FacePalette {
        resolve(FaceColorChoice(background: color), condition: condition)
    }
}
