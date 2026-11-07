import CoreGraphics
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// The Flow face tells the time with drops shaped like digits, laid out in a
/// line on a landscape face and stacked on a portrait one, and widgets keep
/// clear of it.
@Suite struct FlowClockTests {
    @Test func timesBecomeGlyphs() {
        #expect(FlowGlyph.glyphs("10:09") == [.digit(1), .digit(0), .colon, .digit(0), .digit(9)])
        #expect(FlowGlyph.glyphs("9:41") == [.digit(9), .colon, .digit(4), .digit(1)])
    }

    @Test func everyGlyphIsOneShapeInsideItsCell() {
        for glyph in (0...9).map(FlowGlyph.digit) + [.colon] {
            let bounds = glyph.outline.boundingRect
            let cell = CGRect(x: 0, y: 0, width: glyph.width, height: FlowGlyph.height)
            #expect(!bounds.isEmpty, "\(glyph)")
            #expect(cell.insetBy(dx: -0.001, dy: -0.001).contains(bounds), "\(glyph) \(bounds)")
        }
        // Like HomeView's: a 1 is a slab and a dot, a 0 a rounded block.
        #expect(FlowGlyph.digit(1).pieces.count == 2)
        #expect(FlowGlyph.digit(0).pieces.count == 1)
    }

    @Test func landscapeIsOneLineAndPortraitStacksTheHours() {
        let insets = Theme.Spacing.screenContent
        let line = FlowClockLayout.make(FlowGlyph.glyphs("10:09"), size: CGSize(width: 1210, height: 834), insets: insets)
        #expect(line.placed.count == 5)
        #expect(Set(line.placed.map(\.frame.minY)).count == 1)
        let stack = FlowClockLayout.make(FlowGlyph.glyphs("10:09"), size: CGSize(width: 834, height: 1210), insets: insets)
        #expect(stack.placed.map(\.glyph) == [.digit(1), .digit(0), .digit(0), .digit(9)], "no colon when stacked")
        #expect(stack.placed[2].frame.minY > stack.placed[0].frame.maxY)
    }

    @MainActor @Test func theTimeKeepsInsideItsBlockAndLeavesRoomForWidgets() throws {
        let support = try #require(FaceCatalog.definition("faces.flow")).widgets
        for screen in FaceWidgetRoomTests.screens {
            let (size, insets) = FaceWidgetRoomTests.wall(screen, overscan: 8)
            for time in ["10:09", "9:41", "1:11", "00:00", "12:58"] {
                let layout = FlowClockLayout.make(FlowGlyph.glyphs(time), size: size, insets: insets)
                for placed in layout.placed {
                    #expect(layout.bounds.insetBy(dx: -0.5, dy: -0.5).contains(placed.frame), "\(screen) \(time)")
                }
            }
            let open = FaceWidgetRoomTests.openFrames(support, faceID: "faces.flow", size: size, insets: insets)
            let block = FlowClockLayout.make([], size: size, insets: insets).bounds
            #expect(open.count >= 8, "\(screen) has room for widgets")
            for cell in open {
                #expect(!cell.insetBy(dx: 14, dy: 14).intersects(block), "\(screen) cell \(cell)")
            }
            // Big enough to read across the room.
            #expect(block.height > min(size.width, size.height) * 0.33, "\(screen)")
        }
    }
}
