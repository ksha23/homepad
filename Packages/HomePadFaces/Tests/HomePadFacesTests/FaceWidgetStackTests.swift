import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Widget stacks on a face: kept once by placement for both orientations,
/// broken back into a widget when one is left, sized by all their widgets,
/// and saved so that faces from before stacks read and save as they were.
@Suite struct FaceWidgetStackTests {
    private static func cell(_ column: Int, _ row: Int) -> FaceGridCell { FaceGridCell(column: column, row: row) }

    private let placement = FaceWidgetPlacement(widgetID: "personal.weather", size: .medium, cell: cell(4, 0))
    private let other = FaceWidgetPlacement(widgetID: "kitchen.timers", size: .small, cell: cell(4, 2))

    private func layout() -> FaceWidgetLayout {
        var portrait = placement
        portrait.cell = nil
        return FaceWidgetLayout(landscape: [placement, other], portrait: [portrait])
    }

    @Test func aStackIsKeptOnceForBothOrientations() throws {
        var layout = layout()
        layout.setStack(.of(["audio.nowplaying", "personal.weather"]), for: placement.id)
        #expect(layout.stack(for: placement.id)?.members.map(\.widgetID) == ["audio.nowplaying", "personal.weather"])
        // Both orientations name the stack's first widget, which a HomePad from before stacks shows.
        #expect(layout.landscape?.first?.widgetID == "audio.nowplaying")
        #expect(layout.portrait?.first?.widgetID == "audio.nowplaying")
        #expect(layout.members(of: other).map(\.widgetID) == ["kitchen.timers"], "a widget is a stack of one")
        let decoded = try JSONDecoder().decode(FaceWidgetLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }

    @Test func aStackWithOneWidgetLeftBecomesThatWidget() {
        let list = WidgetSettingKey<String?>("list", default: nil)
        var groceries = WidgetSettings()
        groceries[list] = "groceries"
        var layout = layout()
        layout.setStack(WidgetStack(members: [WidgetStack.Member(widgetID: "audio.nowplaying"),
                                              WidgetStack.Member(widgetID: "personal.reminders", settings: groceries)]),
                        for: placement.id)
        var stack = layout.stack(for: placement.id) ?? WidgetStack(members: [])
        stack.members.removeFirst()
        layout.setStack(stack, for: placement.id)
        #expect(layout.stack(for: placement.id) == nil)
        #expect(layout.stacks == nil, "a face with no stacks saves none")
        #expect(layout.landscape?.first?.widgetID == "personal.reminders")
        #expect(layout.portrait?.first?.widgetID == "personal.reminders")
        #expect(layout.settings(for: placement.id)[list] == "groceries", "it keeps its own settings")
        // None left takes it off the face in both orientations.
        layout.setStack(WidgetStack(members: []), for: placement.id)
        #expect(layout.landscape?.map(\.id) == [other.id])
        #expect(layout.portrait?.isEmpty == true)
        #expect(layout.widgetSettings == nil)
    }

    @Test func removingAStackTakesItsWidgetsWithIt() {
        var layout = layout()
        layout.setStack(.of(["audio.nowplaying", "personal.weather"]), for: placement.id)
        layout.save([other], for: .landscape)
        #expect(layout.stacks == nil)
        #expect(layout.portrait?.map(\.id) == [other.id], "it leaves portrait too")
    }

    /// Faces saved before stacks decode as they were and save in the same shape.
    @Test func layoutsSavedBeforeStacksStayAsTheyWere() throws {
        let json = #"{"landscape":[{"id":"FACE0000-0000-4000-8000-000000000002","widget":"a","size":"large","cell":{"column":4,"row":0}}],"widgetSettings":{"FACE0000-0000-4000-8000-000000000002":{"list":"x"}}}"#
        let layout = try JSONDecoder().decode(FaceWidgetLayout.self, from: Data(json.utf8))
        #expect(layout.stacks == nil)
        let before = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? NSDictionary
        #expect(before == after)
    }

    /// A stack takes only the sizes all its widgets come in, and steps down to one when its saved size is not.
    @Test func aStackIsSizedByAllItsWidgets() {
        let grid = FaceGrid(size: CGSize(width: 1210, height: 834), insets: Theme.Spacing.screenContent)
        let large = FaceWidgetPlacement(widgetID: "a", size: .large, cell: Self.cell(0, 0))
        let board = FaceWidgetBoard(placements: [large], grid: grid, fill: .readingOrder,
                                    sizes: { _ in WidgetSize.allCases },
                                    stackSizes: { $0 == large.id ? [.small, .medium] : nil })
        #expect(board.item(large.id)?.size == .medium)
        let gone = FaceWidgetBoard(placements: [large], grid: grid, fill: .readingOrder, stackSizes: { _ in [] })
        #expect(gone.items.isEmpty && gone.leftOut.map(\.id) == [large.id], "a stack whose widgets are all gone waits")
    }

    @Test func theDebugListMakesAStack() throws {
        let layout = try #require(FaceDebugOptions.widgetLayout(from: "personal.upnext+personal.weather:medium@4,0;kitchen.timers:small"))
        let first = try #require(layout.landscape?.first)
        #expect(first.widgetID == "personal.upnext")
        #expect(layout.stack(for: first.id)?.members.map(\.widgetID) == ["personal.upnext", "personal.weather"])
        #expect(layout.stacks?.count == 1)
    }
}
