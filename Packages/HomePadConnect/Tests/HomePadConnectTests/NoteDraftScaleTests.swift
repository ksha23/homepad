import CoreGraphics
import Testing
@testable import HomePadConnect

/// The note being written is the board's note magnified to fill the room the
/// composer has, and it shrinks as lines are added so it stays whole above
/// the keyboard.
@Suite struct NoteDraftScaleTests {
    /// About the room beside the options in landscape on the 11-inch iPad
    /// with the on-screen keyboard up.
    let besideTheKeyboard = CGSize(width: 330, height: 286)

    /// A board note at the default text size: 240 wide, a 21 point byline
    /// and 34 point lines of text.
    private func note(lines: Int) -> NoteDraftScale {
        NoteDraftScale(width: 240, padding: 16, spacing: 6,
                       metrics: NoteDraftMetrics(byline: 21, text: CGFloat(lines) * 34, line: 34))
    }

    @Test func aShortNoteGrowsToTheLargestScale() {
        #expect(note(lines: 1).scale(in: CGSize(width: 700, height: 600)) == NoteDraftScale.range.upperBound)
    }

    @Test func aShortNoteFillsTheWidthBesideTheKeyboard() {
        #expect(abs(note(lines: 1).scale(in: besideTheKeyboard) - 330.0 / 240.0) < 0.0001)
    }

    @Test func moreLinesNeverMakeTheNoteLarger() {
        var previous = CGFloat.infinity
        for lines in 1...14 {
            let scale = note(lines: lines).scale(in: besideTheKeyboard)
            #expect(scale <= previous, "\(lines) lines")
            previous = scale
        }
    }

    /// Until the smallest scale, the whole note fits the room.
    @Test(arguments: 1...8)
    func theWholeNoteFitsAboveTheKeyboard(lines: Int) {
        let sizing = note(lines: lines)
        let scale = sizing.scale(in: besideTheKeyboard)
        #expect(sizing.height * scale <= besideTheKeyboard.height + 0.001)
        #expect(sizing.width * scale <= besideTheKeyboard.width + 0.001)
        #expect(sizing.maxLines(in: besideTheKeyboard, scale: scale) >= lines)
    }

    /// Past the smallest scale the text scrolls inside the note, which shows
    /// as many lines as fit.
    @Test func aLongNoteScrollsAtTheSmallestScale() {
        let sizing = note(lines: 20)
        let scale = sizing.scale(in: besideTheKeyboard)
        #expect(scale == NoteDraftScale.range.lowerBound)
        let lines = sizing.maxLines(in: besideTheKeyboard, scale: scale)
        #expect(lines == 8)
        #expect((sizing.chrome + CGFloat(lines) * 34) * scale <= besideTheKeyboard.height)
    }

    /// Before the note is measured it still draws, at a scale within range.
    @Test func anUnmeasuredNoteHasAScale() {
        let sizing = NoteDraftScale(width: 240, padding: 16, spacing: 6, metrics: NoteDraftMetrics())
        #expect(NoteDraftScale.range.contains(sizing.scale(in: besideTheKeyboard)))
        #expect(sizing.maxLines(in: besideTheKeyboard, scale: 1) == 1)
    }
}
