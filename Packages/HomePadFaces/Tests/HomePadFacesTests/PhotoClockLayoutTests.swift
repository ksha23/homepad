import CoreGraphics
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// The Photos face's time: much larger from across the room, one view
/// shrunk into place up close, and measured where its numerals are drawn.
@Suite struct PhotoClockLayoutTests {
    private static let metrics = ClockFontMetrics.sample

    @Test func theClockFontsAreMeasuredFromTheirDigits() {
        for uses24Hour in [false, true] {
            let depth = ClockFontMetrics.depth(uses24Hour: uses24Hour)
            // Close to the sample the layout tests use, and a line that holds its digits.
            #expect(abs(depth.width - Self.metrics.width) < 0.15, "\(depth)")
            #expect(abs(depth.digitHeight - Self.metrics.digitHeight) < 0.05, "\(depth)")
            #expect(abs(depth.digitTop - Self.metrics.digitTop) < 0.08, "\(depth)")
            #expect(depth.digitTop + depth.digitHeight < depth.lineHeight, "\(depth)")
            let rounded = ClockFontMetrics.rounded(uses24Hour: uses24Hour)
            #expect(rounded.width > depth.width * 1.3, "rounded digits are wider, \(rounded)")
        }
    }

    @MainActor @Test func fromAcrossTheRoomTheDepthTimeIsMuchLarger() throws {
        let support = try #require(FaceCatalog.definition("faces.photos")).widgets
        for screen in FaceWidgetRoomTests.screens {
            let (size, base) = FaceWidgetRoomTests.wall(screen, overscan: 8)
            let insets = FaceWidgetRoomTests.insets(support, size: size, base: base, hasWidgets: true)
            let layout = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: Self.metrics)
            let far = layout.digits(isNear: false)
            let near = layout.digits(isNear: true)
            #expect(far.height > near.height * 1.7, "\(screen)")
            #expect(far.width > near.width * 1.7, "\(screen)")
            // Far, the numerals span the insets' width (or height) from the top inset.
            let content = FaceWidgetRoomTests.content(size, insets)
            let farPoints = CGRect(x: far.minX * size.width, y: far.minY * size.height,
                                   width: far.width * size.width, height: far.height * size.height)
            #expect(content.insetBy(dx: -0.5, dy: -0.5).contains(farPoints), "\(screen)")
            #expect(abs(farPoints.minY - content.minY) < 0.5, "\(screen)")
            #expect(farPoints.width > content.width * 0.9 || farPoints.height > content.height * 0.9, "\(screen)")
        }
    }

    @Test func theTimeIsOneViewShrunkFromItsFarSize() {
        let (size, insets) = FaceWidgetRoomTests.wall(CGSize(width: 1194, height: 834), overscan: 8)
        let layout = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: Self.metrics)
        // The near line is the far line scaled, so `distanceFrame` lands exactly on it.
        let fitted = DistanceFit.fitted(layout.farLine.size, in: layout.nearLine)
        #expect(abs(fitted.width - layout.nearLine.width) < 0.01)
        #expect(abs(fitted.height - layout.nearLine.height) < 0.01)
        #expect(abs(layout.nearLine.height / layout.farLine.height - layout.nearScale) < 0.001)
        // The digits the depth effect measures scale with it.
        let far = layout.digits(isNear: false)
        let near = layout.digits(isNear: true)
        #expect(abs(near.width / far.width - layout.nearScale) < 0.001)
        #expect(abs(near.height / far.height - layout.nearScale) < 0.001)
    }

    @Test func upCloseTheDateSitsAboveTheNumerals() {
        let (size, insets) = FaceWidgetRoomTests.wall(CGSize(width: 1194, height: 834), overscan: 8)
        let layout = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: Self.metrics)
        let near = layout.digits(isNear: true)
        #expect(layout.date.minY == insets.top)
        #expect(layout.date.maxY < near.minY * size.height)
        #expect(layout.dateSize > 30 && layout.dateSize < 40)
    }

    @MainActor @Test func theGlassNumeralsSitWhereTheLayoutMeasuredThem() {
        // The glass time is drawn from glyph outlines, not `Text`, so the depth
        // effect must still find its digits where `PhotoClockLayout` put them.
        let metrics = ClockFontMetrics.depth(uses24Hour: false)
        let line = GlyphLine("10:00", font: PhotoClock.depthUIFont)
        #expect(abs(line.advance - metrics.width) < 0.01)
        #expect(abs(line.lineHeight - metrics.lineHeight) < 0.01)
        let (size, insets) = FaceWidgetRoomTests.wall(CGSize(width: 1210, height: 834), overscan: 8)
        let layout = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: metrics, isCentered: true)
        let drawn = GlyphLineShape(line: line).path(in: layout.farLine).boundingRect
        let digits = layout.digits(isNear: false)
        #expect(abs(drawn.minY - digits.minY * size.height) < 1)
        #expect(abs(drawn.height - digits.height * size.height) < 1)
        #expect(layout.farLine.insetBy(dx: -1, dy: -1).contains(drawn))
    }

    @Test func withoutWidgetsAlongTheBottomTheTimeIsCentered() {
        for screen in FaceWidgetRoomTests.screens {
            let (size, insets) = FaceWidgetRoomTests.wall(screen, overscan: 8)
            let top = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: Self.metrics)
            let centered = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: Self.metrics, isCentered: true)
            let content = FaceWidgetRoomTests.content(size, insets)
            // The same sizes, moved to the middle of the height the insets leave.
            #expect(centered.fontSize == top.fontSize, "\(screen)")
            #expect(abs(centered.nearScale - top.nearScale) < 0.001, "\(screen)")
            let far = centered.digits(isNear: false)
            #expect(abs(far.midY * size.height - content.midY) < 0.5, "\(screen)")
            // Up close the date and the numerals under it are centered together.
            let near = centered.digits(isNear: true)
            #expect(centered.date.maxY < near.minY * size.height, "\(screen)")
            #expect(abs((centered.date.minY + near.maxY * size.height) / 2 - content.midY) < 0.5, "\(screen)")
        }
    }

    @MainActor @Test func onTheIPadsTheWidgetAreaLeavesTheFarTimeItsSize() throws {
        // Widgets show at every distance. On the 11 and 13 inch iPads the far
        // time is as wide as the insets allow and still clears them.
        let support = try #require(FaceCatalog.definition("faces.photos")).widgets
        for screen in FaceWidgetRoomTests.screens {
            let (size, base) = FaceWidgetRoomTests.wall(screen, overscan: 8)
            let insets = FaceWidgetRoomTests.insets(support, size: size, base: base, hasWidgets: true)
            let with = PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: Self.metrics)
            let without = PhotoClockLayout.depth(viewSize: size, insets: base, metrics: Self.metrics)
            #expect(with.farLine == without.farLine, "\(screen)")
        }
        // On a short face the widgets make the time smaller at both distances.
        let short = CGSize(width: 1400, height: 500)
        let base = Theme.Spacing.screenContent
        let insets = FaceWidgetRoomTests.insets(support, size: short, base: base, hasWidgets: true)
        let squeezed = PhotoClockLayout.depth(viewSize: short, insets: insets, metrics: Self.metrics)
        let free = PhotoClockLayout.depth(viewSize: short, insets: base, metrics: Self.metrics)
        #expect(squeezed.fontSize < free.fontSize)
        #expect(squeezed.digits(isNear: true).height < free.digits(isNear: true).height)
    }

    @Test func theClassicTimeShrinksToItsOldSizeUpClose() {
        for screen in FaceWidgetRoomTests.screens {
            let size = screen
            let insets = Theme.Spacing.screenContent
            let layout = PhotoClockLayout.classic(viewSize: size, insets: insets, metrics: Self.metrics)
            let near = layout.fontSize * layout.nearScale
            #expect(abs(near - PhotoClockLayout.classicNearSize(viewSize: size)) < 0.01, "\(screen)")
            #expect(layout.fontSize > near * 1.5, "\(screen)")
            // Both start at the same top, and the date comes under the near time.
            #expect(abs(layout.farLine.minY - layout.nearLine.minY) < 0.01)
            #expect(layout.date.minY > layout.nearLine.maxY)
            #expect(layout.farLine.width <= size.width - insets.leading - insets.trailing + 0.5)
        }
    }
}

extension ClockFontMetrics {
    /// About SF Pro Compressed Semibold's shape in the iPadOS 27 simulator
    /// ("00:00" measured 1.77 wide), so layout tests do not depend on the
    /// fonts installed.
    static let sample = ClockFontMetrics(width: 1.7, lineHeight: 1.19, digitTop: 0.24, digitHeight: 0.72)
}
