import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

@Suite struct LayoutMathTests {
    @Test func tilesPackLeftToRightAndSkipWhatDoesNotFit() {
        let placements = TileGridPacker.pack(widths: [1, 2, 1, 1, 2, 1], columns: 3, rows: 2)
        // The second wide tile (index 4) has no room left, so the last small tile takes the corner.
        #expect(placements.map(\.index) == [0, 1, 2, 3, 5])
        #expect(placements[1] == TilePlacement(index: 1, column: 1, row: 0, width: 2))
        #expect(placements[4] == TilePlacement(index: 5, column: 2, row: 1, width: 1))
    }

    @Test func packingStopsWhenTheGridIsFull() {
        let placements = TileGridPacker.pack(widths: Array(repeating: 1, count: 20), columns: 4, rows: 3)
        #expect(placements.count == 12)
        #expect(placements.last == TilePlacement(index: 11, column: 3, row: 2, width: 1))
    }

    @Test func wideTilesWrapToTheNextRow() {
        let placements = TileGridPacker.pack(widths: [1, 1, 2], columns: 3, rows: 2)
        #expect(placements[2] == TilePlacement(index: 2, column: 0, row: 1, width: 2))
    }

    @Test func cameraGridsStayBalanced() {
        let landscape = CGSize(width: 1376, height: 1032)
        #expect(GridMath.dimensions(count: 1, in: landscape, cellAspect: 16 / 9) == .init(columns: 1, rows: 1))
        #expect(GridMath.dimensions(count: 4, in: landscape, cellAspect: 16 / 9) == .init(columns: 2, rows: 2))
        #expect(GridMath.dimensions(count: 9, in: landscape, cellAspect: 16 / 9) == .init(columns: 3, rows: 3))
        let portrait = CGSize(width: 1032, height: 1376)
        #expect(GridMath.dimensions(count: 6, in: portrait, cellAspect: 16 / 9) == .init(columns: 2, rows: 3))
    }

    @Test func monthGridHasSixWeeksAndMarksToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.firstWeekday = 1
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let grid = MonthGrid.make(for: today, calendar: calendar)
        #expect(grid.days.count == 42)
        #expect(grid.weekdaySymbols.count == 7)
        // October 1, 2026 is a Thursday, so the grid starts on Sunday September 27.
        #expect(grid.days[0].number == 27)
        #expect(!grid.days[0].isInMonth)
        #expect(grid.days[4].number == 1)
        #expect(grid.days.filter(\.isToday).map(\.number) == [20])
        #expect(grid.days.filter(\.isInMonth).count == 31)
    }

    @Test func mondayFirstCalendarsShiftTheGrid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let grid = MonthGrid.make(for: today, calendar: calendar)
        #expect(grid.days[0].number == 28)
        #expect(grid.days[3].number == 1)
    }

    @Test func maskCoverageCountsTheSubject() {
        // Left half subject, right half background, 4 by 2.
        let mask = MaskSample(width: 4, height: 2, values: [255, 255, 0, 0, 255, 255, 0, 0])
        #expect(mask.coverage(in: CGRect(x: 0, y: 0, width: 1, height: 1)) == 0.5)
        #expect(mask.coverage(in: CGRect(x: 0, y: 0, width: 0.5, height: 1)) == 1)
        #expect(mask.coverage(in: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)) == 0)
        #expect(mask.subjectBounds == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(MaskSample(width: 2, height: 1, values: [0, 0]).subjectBounds == nil)
    }

    @Test func aspectFillMapsViewRectsIntoTheImage() {
        // A square image in a 2:1 view shows the middle half of the image vertically.
        let rect = DepthLayout.imageRect(forViewRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                         viewSize: CGSize(width: 200, height: 100), imageSize: CGSize(width: 1000, height: 1000))
        #expect(abs(rect.minY - 0.25) < 0.0001)
        #expect(abs(rect.height - 0.5) < 0.0001)
        #expect(abs(rect.width - 1) < 0.0001)
    }

    @Test func depthNeedsASubjectThatLeavesTheTimeReadable() {
        #expect(DepthLayout.usesDepth(timeCoverage: 0.2, subjectCoverage: 0.3))
        #expect(!DepthLayout.usesDepth(timeCoverage: 0.6, subjectCoverage: 0.3))
        #expect(!DepthLayout.usesDepth(timeCoverage: 0.45, subjectCoverage: 0.3), "a third hidden is the most that still reads")
        #expect(!DepthLayout.usesDepth(timeCoverage: 0, subjectCoverage: 0))
    }

    @Test func kenBurnsAlternatesAndAimsAtTheSubject() {
        let zoomIn = KenBurnsMotion.make(seed: 0, subject: CGRect(x: 0.6, y: 0.5, width: 0.2, height: 0.4))
        let zoomOut = KenBurnsMotion.make(seed: 1, subject: nil)
        #expect(zoomIn.endScale > zoomIn.startScale)
        #expect(zoomOut.endScale < zoomOut.startScale)
        #expect(abs(zoomIn.anchor.x - 0.7) < 0.0001)
        #expect(min(zoomIn.startScale, zoomIn.endScale) >= 1)
    }

    @Test func photoTintsAreLightAndSoft() {
        let tint = PhotoTint(red: 0.8, green: 0.2, blue: 0.3).numeralTint()
        let (_, saturation, value) = tint.hsv
        #expect(abs(value - 0.97) < 0.01)
        #expect(saturation <= 0.37)
        let (hue, _, _) = PhotoTint(red: 0, green: 0, blue: 1).hsv
        #expect(abs(hue - 2.0 / 3.0) < 0.001)
    }

    @Test func flowTimeGrowsAsSomeoneApproaches() {
        let levels = [0, 1, 2, 3].map(FlowMotion.intensity(for:))
        let scales = levels.map { FlowMotion.clockScale(intensity: $0) }
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 < $1 })
        #expect(scales.last == 1, "full size within arm's reach")
        // The drops only bob: never more than a twentieth of a digit.
        for index in 0..<5 {
            for time in stride(from: 0.0, through: 600, by: 7) {
                let drift = FlowMotion.drift(time: time, index: index)
                #expect(abs(drift.x) <= 0.05 && abs(drift.y) <= 0.05)
            }
        }
        #expect(FlowMotion.meshPoints(time: 42).count == 9)
        #expect(FlowMotion.meshPoints(time: 42)[0] == SIMD2(0, 0))
    }

    @Test func flowEasesItsIntensityOnTheProximitySpring() {
        let spring = Spring.smooth(duration: 0.7)
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let move = FlowMotion.IntensityMove(from: 0.5, to: 0.8, start: start)
        #expect(move.value(at: start, spring: spring) == 0.5)
        let samples = stride(from: 0.05, through: 2, by: 0.05).map { move.value(at: start.addingTimeInterval($0), spring: spring) }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 0.0001 }, "never turns back")
        #expect(samples.allSatisfy { (0.5...0.8).contains($0) })
        #expect(abs(samples.last! - 0.8) < 0.01, "settled after two seconds")
        // Walking away halfway through starts from where it got to.
        let back = move.moving(to: 0.5, at: start.addingTimeInterval(0.2), spring: spring)
        #expect(abs(back.from - move.value(at: start.addingTimeInterval(0.2), spring: spring)) < 0.0001)
        #expect(FlowMotion.IntensityMove(settledAt: 1).value(at: start, spring: spring) == 1)
    }

    @MainActor @Test func modularFaceFitsEveryIPad() throws {
        let support = try #require(FaceCatalog.definition("faces.modular")).widgets
        let sizes = [CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366),
                     CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194),
                     CGSize(width: 1376, height: 1032), CGSize(width: 1210, height: 834)]
        for size in sizes {
            let screen = CGRect(origin: .zero, size: size)
            for hasWidgets in [false, true] {
                let insets = FaceWidgetRoomTests.insets(support, size: size, base: Theme.Spacing.screenContent,
                                                        hasWidgets: hasWidgets)
                let layout = ModularLayout(size: size, insets: insets)
                let parts = [layout.hero, layout.lower]
                #expect(parts.allSatisfy { layout.content.insetBy(dx: -0.5, dy: -0.5).contains($0) })
                #expect(screen.contains(layout.content))
                // Nothing overlaps.
                for (index, part) in parts.enumerated() {
                    #expect(parts.dropFirst(index + 1).allSatisfy { !$0.insetBy(dx: 0.5, dy: 0.5).intersects(part) })
                }
                // The info panel keeps a generous share of the screen.
                #expect(layout.info.height >= size.height * 0.5)
                #expect(layout.info.width >= size.width * 0.55)
            }
        }
    }
}

/// Content that reaches the profile button's corner moves clear of it, losing as little room as it can.
@Suite struct ProfileZoneTests {
    private let insets = Theme.Spacing.screenContent

    @Test func contentInTheCornerMovesClear() {
        for size in [CGSize(width: 1210, height: 834), CGSize(width: 834, height: 1210)] {
            let zone = FaceWidgetSupport.profileZone(size: size, insets: insets)
            let cleared = insets.clearing(zone, in: size)
            let content = CGRect(x: cleared.leading, y: cleared.top, width: size.width - cleared.leading - cleared.trailing,
                                 height: size.height - cleared.top - cleared.bottom)
            #expect(!content.intersects(zone))
            // Only one edge moves.
            #expect((cleared.top == insets.top) != (cleared.trailing == insets.trailing))
        }
        // Wide: the trailing edge moves in. Tall: the top comes down.
        let wide = CGSize(width: 1210, height: 834)
        #expect(insets.clearing(FaceWidgetSupport.profileZone(size: wide, insets: insets), in: wide).top == insets.top)
        let tall = CGSize(width: 834, height: 1210)
        #expect(insets.clearing(FaceWidgetSupport.profileZone(size: tall, insets: insets), in: tall).trailing == insets.trailing)
    }

    @Test func contentAlreadyClearStaysPut() {
        let size = CGSize(width: 1210, height: 834)
        let zone = FaceWidgetSupport.profileZone(size: size, insets: insets)
        let wide = EdgeInsets(top: zone.maxY, leading: 64, bottom: 44, trailing: 64)
        #expect(wide.clearing(zone, in: size) == wide)
        #expect(insets.clearing(.null, in: size) == insets)
    }

    /// Weather's time moves out from under the button to just before it, on its center line.
    @Test func weathersTimeSitsBesideTheButton() {
        let size = CGSize(width: 1210, height: 834)
        let zone = FaceWidgetSupport.profileZone(size: size, insets: insets)
        let spot = WeatherFace.timeSpot(size: size, insets: insets, profileZone: zone)
        #expect(spot.top == Theme.Size.profileButtonInset && spot.height == Theme.Size.profileButton)
        #expect(size.width - spot.trailing <= zone.minX)
        // Thumbnails have no button, and widgets beside the face keep the time clear of it already.
        #expect(WeatherFace.timeSpot(size: size, insets: insets, profileZone: .null).top == insets.top)
        var beside = insets
        beside.trailing = 400
        #expect(WeatherFace.timeSpot(size: size, insets: beside, profileZone: zone).trailing == 400)
    }
}
