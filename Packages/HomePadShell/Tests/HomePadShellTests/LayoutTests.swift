import Foundation
import HomePadCore
import HomePadUI
import Testing
@testable import HomePadShell

@Suite struct GridPackerTests {
    @Test func packsFirstFitInReadingOrder() {
        // Four apps, a large widget, then three more apps on a 4 x 3 grid.
        let spans = Array(repeating: GridSpan.one, count: 4) + [GridSpan(.large)] + Array(repeating: .one, count: 3)
        let pages = GridPacker.paginate(spans, columns: 4, rows: 3)
        #expect(pages.count == 1)
        let placements = pages[0]
        #expect(placements[4].column == 0 && placements[4].row == 1)
        #expect(placements[5].column == 2 && placements[5].row == 1)
        #expect(placements[6].column == 3 && placements[6].row == 1)
        #expect(placements[7].column == 2 && placements[7].row == 2)
    }

    @Test func overflowStartsANewPage() {
        let pages = GridPacker.paginate(Array(repeating: .one, count: 7), columns: 3, rows: 2)
        #expect(pages.map(\.count) == [6, 1])
        #expect(pages[1][0].index == 6)
    }

    @Test func clampsSpansWiderThanTheGrid() {
        let pages = GridPacker.paginate([GridSpan(columns: 4, rows: 4)], columns: 2, rows: 2)
        #expect(pages[0][0].span == GridSpan(columns: 2, rows: 2))
    }

    /// A tall widget takes two columns and three rows, and icons flow beside it.
    @Test func packsATallWidgetBesideIcons() {
        #expect(GridSpan(.tall) == GridSpan(columns: 2, rows: 3))
        let spans = [GridSpan(.tall)] + Array(repeating: GridSpan.one, count: 5)
        let pages = GridPacker.paginate(spans, columns: 4, rows: 3)
        #expect(pages.count == 1)
        #expect(pages[0][0].span == GridSpan(columns: 2, rows: 3))
        #expect(pages[0].dropFirst().map(\.column) == [2, 3, 2, 3, 2])
        #expect(pages[0].dropFirst().map(\.row) == [0, 0, 1, 1, 2])
    }

    /// At the largest text sizes a landscape page can have only two rows: a tall widget takes both.
    @Test func clampsATallWidgetToAShortPage() {
        let pages = GridPacker.paginate([GridSpan(.tall), .one], columns: 5, rows: 2)
        #expect(pages.count == 1)
        #expect(pages[0][0].span == GridSpan(columns: 2, rows: 2))
        #expect(pages[0][1].column == 2)
    }

    /// Under three large widgets one row is left, so a tall widget goes on the next page.
    @Test func aTallWidgetWithoutThreeFreeRowsStartsANewPage() {
        let spans = [GridSpan(.large), GridSpan(.large), GridSpan(.large), GridSpan(.tall), .one]
        let pages = GridPacker.paginate(spans, columns: 6, rows: 3)
        #expect(pages.count == 2)
        #expect(pages[1].first?.index == 3)
        #expect(pages[1].first?.span == GridSpan(columns: 2, rows: 3))
    }

    @Test func emptyInputGivesOneEmptyPage() {
        #expect(GridPacker.paginate([], columns: 4, rows: 4).map(\.count) == [0])
    }

    @Test func unboundedPackGrowsDownward() {
        let placements = GridPacker.pack(Array(repeating: GridSpan(columns: 2, rows: 1), count: 5), columns: 4)
        #expect(placements.count == 5)
        #expect(placements.last?.row == 2)
    }
}

@Suite struct HomeScreenLayoutTests {
    private let apps = (1...10).map { "app\($0)" }

    @Test func defaultIsOneCuratedPageThatFillsTheScreen() {
        let widgets: [(id: String, sizes: [WidgetSize])] = [
            ("audio.nowplaying", [.medium]), ("personal.weather", [.small, .medium]),
            ("smarthome.favorites", WidgetSize.allCases), ("smarthome.scenes", [.medium]),
            ("personal.upnext", [.medium, .large]), ("other.widget", [.small]),
        ]
        let appIDs = ["zeta", "music", "home", "assistant", "cameras", "alpha"]
        let layout = HomeScreenLayout.makeDefault(appIDs: appIDs, widgets: widgets)
        #expect(layout.pages.count == 1)
        #expect(layout.pages[0].map(\.targetID) == [
            "smarthome.favorites", "personal.weather", "personal.upnext",
            "home", "cameras", "assistant", "music",
            "audio.nowplaying", "smarthome.scenes",
            "zeta", "alpha",
        ])
        #expect(layout.pages[0][0] == .widget("smarthome.favorites", size: .large))
        #expect(!layout.contains(HomeScreenItem.widget("other.widget", size: .small).id))
    }

    @Test func defaultFallsBackToTheFirstWidget() {
        let layout = HomeScreenLayout.makeDefault(appIDs: apps, widgets: [("weather", WidgetSize.allCases), ("music", [.small, .medium])])
        #expect(layout.pages.count == 1)
        #expect(layout.pages[0].first?.targetID == "weather")
        #expect(layout.pages[0].filter { $0.kind == .app }.count == apps.count)
    }

    @Test func newAppsAppearButRemovedOnesStayRemoved() {
        var layout = HomeScreenLayout.makeDefault(appIDs: ["a", "b"], widgets: [])
        layout.remove(HomeScreenItem.app("a").id)
        let reconciled = layout.reconciled(withAppIDs: ["a", "b", "c"])
        #expect(!reconciled.contains(HomeScreenItem.app("a").id))
        #expect(reconciled.pages.last?.last == HomeScreenItem.app("c"))
    }

    @Test func movesBeforeAnItemOnAnotherPage() {
        var layout = HomeScreenLayout(pages: [[.app("a"), .app("b")], [.app("c")]], knownAppIDs: ["a", "b", "c"])
        layout.move(HomeScreenItem.app("a").id, before: HomeScreenItem.app("c").id)
        #expect(layout.pages == [[.app("b")], [.app("a"), .app("c")]])
    }

    @Test func movesToTheEndOfAPage() {
        var layout = HomeScreenLayout(pages: [[.app("a"), .app("b")], []], knownAppIDs: ["a", "b"])
        layout.move(HomeScreenItem.app("a").id, toEndOfPage: 1)
        #expect(layout.pages == [[.app("b")], [.app("a")]])
    }

    @Test func addsOnceAndResizesWidgets() {
        var layout = HomeScreenLayout(pages: [[]], knownAppIDs: [])
        layout.add(.widget("w", size: .small), toPage: 0)
        layout.add(.widget("w", size: .large), toPage: 0)
        #expect(layout.allItems.count == 1)
        layout.resize(HomeScreenItem.widget("w", size: .small).id, to: .medium)
        #expect(layout.allItems.first?.widgetSize == .medium)
    }

    @Test func aTallWidgetIsSavedTall() throws {
        let layout = HomeScreenLayout(pages: [[.widget("w", size: .tall)]], knownAppIDs: [])
        let decoded = try JSONDecoder().decode(HomeScreenLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded.allItems.first?.widgetSize == .tall)
        #expect(decoded.allItems.first?.span == GridSpan(columns: 2, rows: 3))
    }

    /// Layouts saved before widget copies and settings decode as they were,
    /// keep their item IDs, and save in the same shape until something changes.
    @Test func layoutsSavedBeforeWidgetSettingsDecode() throws {
        let json = #"{"pages":[[{"kind":"widget","targetID":"personal.reminders","size":"large"},{"kind":"app","targetID":"home"}]],"knownAppIDs":["home"]}"#
        let layout = try JSONDecoder().decode(HomeScreenLayout.self, from: Data(json.utf8))
        #expect(layout.allItems.map(\.id) == ["widget:personal.reminders", "app:home"])
        #expect(layout.allItems.first?.widgetSize == .large)
        #expect(layout.settings(for: "widget:personal.reminders").isEmpty)
        let saved = String(decoding: try JSONEncoder().encode(layout), as: UTF8.self)
        #expect(!saved.contains("instance") && !saved.contains("settings"))
    }

    /// Two copies of one widget keep their own settings, which move and resize
    /// with them, survive a round trip and go when the copy is removed.
    @Test func eachWidgetCopyKeepsItsOwnSettings() throws {
        let list = WidgetSettingKey<String?>("list", default: nil)
        let first = HomeScreenItem.newWidget("personal.reminders", size: .tall)
        let second = HomeScreenItem.newWidget("personal.reminders", size: .medium)
        #expect(first.id != second.id)
        var layout = HomeScreenLayout(pages: [[first, .app("a")], [second]], knownAppIDs: ["a"])
        var groceries = WidgetSettings()
        groceries[list] = "groceries"
        var errands = WidgetSettings()
        errands[list] = "errands"
        layout.setSettings(groceries, for: first.id)
        layout.setSettings(errands, for: second.id)
        layout.move(first.id, toEndOfPage: 1)
        layout.resize(first.id, to: .large)
        let decoded = try JSONDecoder().decode(HomeScreenLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded.pages[1].map(\.id) == [second.id, first.id])
        #expect(decoded.settings(for: first.id)[list] == "groceries")
        #expect(decoded.settings(for: second.id)[list] == "errands")
        #expect(decoded.containsWidget("personal.reminders"))
        // The defaults store nothing.
        layout.setSettings(WidgetSettings(), for: second.id)
        #expect(layout.allItems.first { $0.id == second.id }?.settings == nil)
        layout.remove(first.id)
        #expect(layout.settings(for: first.id).isEmpty)
        #expect(layout.containsWidget("personal.reminders"))
    }

    @Test func removingEmptyPagesKeepsOne() {
        var layout = HomeScreenLayout(pages: [[], []], knownAppIDs: [])
        layout.removeEmptyPages()
        #expect(layout.pages.count == 1)
    }

    @Test func placesItemsFirstInOrder() {
        var layout = HomeScreenLayout(pages: [[.app("a"), .widget("w", size: .small)], [.app("b")]], knownAppIDs: ["a", "b"])
        layout.placeFirst([.widget("w", size: .large), .widget("x", size: .medium)])
        #expect(layout.pages == [[.widget("w", size: .large), .widget("x", size: .medium), .app("a")], [.app("b")]])
    }
}

@Suite struct ControlCenterLayoutTests {
    @Test func reconcileAddsOnlyNewTiles() {
        var layout = ControlCenterLayout.makeDefault(availableIDs: ["a", "b"])
        layout.remove("a")
        let reconciled = layout.reconciled(withAvailableIDs: ["a", "b", "c"])
        #expect(reconciled.tileIDs == ["b", "c"])
    }

    @Test func removesAndAddsAtTheEnd() {
        var layout = ControlCenterLayout.makeDefault(availableIDs: ["a", "b", "c"])
        layout.remove("a")
        #expect(layout.tileIDs == ["b", "c"])
        layout.add("a")
        layout.add("b")
        #expect(layout.tileIDs == ["b", "c", "a"])
    }

    @Test func reorderKeepsTilesThatAreNotShowing() {
        // "m" is from a module that is not loaded, so the grid never shows it.
        var layout = ControlCenterLayout.makeDefault(availableIDs: ["a", "m", "b", "c"])
        layout.reorder(visible: ["c", "a", "b"])
        #expect(layout.tileIDs == ["c", "m", "a", "b"])
    }
}

/// Dragging a Control Center tile in edit mode: the others move aside live.
@Suite struct ControlCenterReorderTests {
    /// Tiles in one row, each `widths[id]` cells wide (one by default), 100 points a cell.
    private func row(_ widths: [String: Int] = [:]) -> ([String]) -> [String: CGRect] {
        { ids in
            var x: CGFloat = 0
            var frames: [String: CGRect] = [:]
            for id in ids {
                let width = CGFloat(widths[id] ?? 1) * 100
                frames[id] = CGRect(x: x, y: 0, width: width - 10, height: 90)
                x += width
            }
            return frames
        }
    }

    @Test func takesTheSlotOfTheTileUnderItsCenter() {
        var reorder = ControlCenterReorder(draggedID: "a", order: ["a", "b", "c", "d"])
        let moved = reorder.update(at: CGPoint(x: 245, y: 45), layout: row())
        #expect(moved)
        #expect(reorder.order == ["b", "c", "a", "d"])
    }

    @Test func goingBackToWhereItStartedMovesTheOthersBack() {
        var reorder = ControlCenterReorder(draggedID: "c", order: ["a", "b", "c"])
        let left = reorder.update(at: CGPoint(x: 145, y: 45), layout: row())
        #expect(left)
        #expect(reorder.order == ["a", "c", "b"])
        // Straight back over its first slot, where "b" now sits.
        let back = reorder.update(at: CGPoint(x: 245, y: 45), layout: row())
        #expect(back)
        #expect(reorder.order == ["a", "b", "c"])
    }

    @Test func aWideTileDoesNotFlipBackAndForth() {
        // "b" is two cells wide. Over its right half, taking its place would
        // leave "b" under the point again, so nothing moves.
        let widths = ["b": 2]
        var reorder = ControlCenterReorder(draggedID: "a", order: ["b", "a"])
        let overRightHalf = reorder.update(at: CGPoint(x: 150, y: 45), layout: row(widths))
        #expect(!overRightHalf)
        #expect(reorder.order == ["b", "a"])
        // Over its left half, the dragged tile lands right there.
        let overLeftHalf = reorder.update(at: CGPoint(x: 45, y: 45), layout: row(widths))
        #expect(overLeftHalf)
        #expect(reorder.order == ["a", "b"])
        let again = reorder.update(at: CGPoint(x: 45, y: 45), layout: row(widths))
        #expect(!again)
    }

    @Test func belowEveryTileMovesToTheEnd() {
        var reorder = ControlCenterReorder(draggedID: "b", order: ["a", "b", "c"])
        let moved = reorder.update(at: CGPoint(x: 50, y: 300), layout: row())
        #expect(moved)
        #expect(reorder.order == ["a", "c", "b"])
        let again = reorder.update(at: CGPoint(x: 50, y: 300), layout: row())
        #expect(!again)
    }

    @Test func gapsBetweenTilesChangeNothing() {
        var reorder = ControlCenterReorder(draggedID: "a", order: ["a", "b", "c"])
        let moved = reorder.update(at: CGPoint(x: 95, y: 45), layout: row())
        #expect(!moved)
        #expect(reorder.order == ["a", "b", "c"])
    }
}

@Suite struct SmallLogicTests {
    @Test func faceResolutionOrder() {
        let faces = ["faces.photos", "faces.modular", FaceResolver.builtInClockID]
        #expect(FaceResolver.resolve(override: "faces.photos", memberPreference: "faces.modular", defaultID: "x", available: faces) == "faces.photos")
        #expect(FaceResolver.resolve(override: "missing", memberPreference: "faces.modular", defaultID: "x", available: faces) == "faces.modular")
        #expect(FaceResolver.resolve(override: nil, memberPreference: nil, defaultID: FaceResolver.builtInClockID, available: faces) == FaceResolver.builtInClockID)
        #expect(FaceResolver.resolve(override: nil, memberPreference: nil, defaultID: "missing", available: faces) == "faces.photos")
        #expect(FaceResolver.resolve(override: nil, memberPreference: nil, defaultID: "missing", available: []) == nil)
    }

    @Test(arguments: [(7, "Good morning, Margot"), (13, "Good afternoon, Margot"), (19, "Good evening, Margot"), (2, "Hello, Margot")])
    func greetings(hour: Int, expected: String) {
        #expect(Greeting.text(for: TestDates.date(hour: hour), name: "Margot") == expected)
    }

    @Test func greetingWithoutAName() {
        #expect(Greeting.text(for: TestDates.date(hour: 8), name: nil) == "Good morning")
    }

    /// HomeView's header: the greeting over the name, or the date over the time.
    @Test func headerLines() {
        let greeting = HomeHeaderLines.greeting(TestDates.date(hour: 8), name: "Margot")
        #expect(greeting == HomeHeaderLines(top: "Good morning,", bottom: "Margot", isGreeting: true))
        let date = HomeHeaderLines.date(TestDates.date(hour: 8))
        #expect(!date.isGreeting && date.bottom.contains(":"))
    }

    /// The header's text and the profile button follow the icons, about HomeView's proportions.
    @Test func headerScalesWithTheIcons() {
        #expect(HomeScreenHeader.textSize(iconSize: 93) == 22)
        #expect(HomeScreenHeader.textSize(iconSize: 110) > HomeScreenHeader.textSize(iconSize: 93))
    }
}

@Suite struct ClockFormatTests {
    @Test func dropsTheDayPeriodAndLeadingZero() {
        let date = TestDates.date(hour: 4, minute: 7)
        #expect(date.clockTime(locale: Locale(identifier: "en_US")) == "4:07")
        #expect(TestDates.date(hour: 16, minute: 30).clockTime(locale: Locale(identifier: "en_GB")) == "16:30")
    }
}

@Suite struct HomeGridMetricsTests {
    /// The page area for each iPad size in landscape, roughly as the Home Screen lays it out.
    @Test(arguments: [CGSize(width: 1138, height: 650), CGSize(width: 1294, height: 840)])
    func rowsFillThePageHeight(size: CGSize) {
        let metrics = HomeGridMetrics(size: size, prefersLargerCells: false)
        let bottom = metrics.frame(for: GridPlacement(index: 0, column: 0, row: metrics.rows - 1, span: .one)).maxY
        #expect(abs(bottom - size.height) < 0.5)
        #expect(metrics.cellSize.height >= metrics.cellSize.width * 0.92)
    }

    @Test func tooShortPagesKeepTheNaturalCellShape() {
        let metrics = HomeGridMetrics(size: CGSize(width: 1138, height: 100), prefersLargerCells: false)
        #expect(metrics.rows == 1)
        #expect(abs(metrics.cellSize.height - metrics.cellSize.width * 0.92) < 0.01)
    }
}
