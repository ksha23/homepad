import CoreGraphics
import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

/// Widget stacks on the Home Screen: made by dropping a widget on another of
/// its size, broken back into a widget when one is left, and saved so that
/// layouts from before stacks read and save as they were.
@Suite struct HomeScreenStackTests {
    private let weather = HomeScreenItem.widget("personal.weather", size: .medium)
    private let music = HomeScreenItem.newWidget("audio.nowplaying", size: .medium)
    private let timers = HomeScreenItem.widget("kitchen.timers", size: .small)

    private func layout() -> HomeScreenLayout {
        HomeScreenLayout(pages: [[weather, .app("home"), music, timers]], knownAppIDs: ["home"])
    }

    @Test func droppingAWidgetOnOneOfItsSizeMakesAStack() throws {
        var layout = layout()
        #expect(layout.canStack(music.id, onto: weather.id))
        #expect(!layout.canStack(timers.id, onto: weather.id), "a small widget does not stack on a medium one")
        #expect(!layout.canStack(HomeScreenItem.app("home").id, onto: weather.id), "an app does not stack")
        #expect(!layout.canStack(weather.id, onto: weather.id))
        let stacked = layout.stack(music.id, onto: weather.id)
        let id = try #require(stacked)
        // The stack takes the target's place and the dropped widget comes off the page.
        #expect(layout.pages[0].map(\.id) == [id, "app:home", timers.id])
        let stack = try #require(layout.stack(for: id))
        // The dropped widget is on top, as on iPadOS.
        #expect(stack.members.map(\.widgetID) == ["audio.nowplaying", "personal.weather"])
        #expect(stack.members[0].id == music.instance, "the dropped widget keeps its copy's ID")
        #expect(id.hasPrefix("stack:"))
        #expect(layout.allItems[0].targetID == "audio.nowplaying", "an older HomePad shows the first widget")
        #expect(layout.containsWidget("personal.weather") && layout.containsWidget("audio.nowplaying"))
    }

    @Test func droppingOnAStackPutsTheWidgetsOnTopUpToTen() throws {
        var layout = layout()
        let stacked = layout.stack(music.id, onto: weather.id)
        let id = try #require(stacked)
        let other = HomeScreenItem.newWidget("shell.homestatus", size: .medium)
        layout.add(other, toPage: 0)
        let grown = layout.stack(other.id, onto: id)
        let same = try #require(grown)
        #expect(same == id, "a stack keeps its ID as it grows")
        #expect(layout.stack(for: id)?.members.map(\.widgetID) == ["shell.homestatus", "audio.nowplaying", "personal.weather"])
        // Nine more would make twelve.
        let big = try #require(HomeScreenItem.stack(.of((0..<9).map { "w\($0)" }), size: .medium))
        layout.add(big, toPage: 0)
        #expect(!layout.canStack(big.id, onto: id))
        let refused = layout.stack(big.id, onto: id)
        #expect(refused == nil)
    }

    @Test func aStackWithOneWidgetLeftBecomesThatWidget() throws {
        let list = WidgetSettingKey<String?>("list", default: nil)
        var groceries = WidgetSettings()
        groceries[list] = "groceries"
        let member = WidgetStack.Member(id: "copy", widgetID: "personal.reminders", settings: groceries)
        let item = try #require(HomeScreenItem.stack(WidgetStack(members: [member, WidgetStack.Member(widgetID: "a")]),
                                                     size: .large))
        var layout = HomeScreenLayout(pages: [[.app("home"), item]], knownAppIDs: ["home"])
        var stack = try #require(layout.stack(for: item.id))
        stack.members.removeLast()
        layout.setStack(stack, for: item.id)
        let widget = layout.pages[0][1]
        #expect(!widget.isStack)
        #expect(widget.id == "widget:personal.reminders:copy")
        #expect(widget.widgetSize == .large)
        #expect(layout.settings(for: widget.id)[list] == "groceries", "it keeps its own settings")
        // A stack of one cannot be made, and none left takes the place off.
        #expect(HomeScreenItem.stack(WidgetStack(members: [member]), size: .small)?.isStack == false)
        let pair = try #require(HomeScreenItem.stack(.of(["a", "b"]), size: .small))
        layout.add(pair, toPage: 0)
        layout.setStack(WidgetStack(members: []), for: pair.id)
        #expect(!layout.contains(pair.id))
    }

    /// Layouts saved before stacks decode as they were and save in the same shape.
    @Test func layoutsSavedBeforeStacksStayAsTheyWere() throws {
        let json = #"{"pages":[[{"kind":"widget","targetID":"personal.reminders","size":"large","instance":"A","settings":{"list":"groceries"}},{"kind":"app","targetID":"home"}]],"knownAppIDs":["home"],"miniWidget":{"widgetID":"shell.glance.mini","size":"small"}}"#
        let layout = try JSONDecoder().decode(HomeScreenLayout.self, from: Data(json.utf8))
        #expect(layout.allItems.map(\.id) == ["widget:personal.reminders:A", "app:home"])
        #expect(layout.allItems.allSatisfy { !$0.isStack })
        let saved = try JSONEncoder().encode(layout)
        let before = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: saved) as? NSDictionary
        #expect(before == after)
    }

    /// A stack survives a round trip, and an older HomePad reading it finds a widget, its first.
    @Test func aStackIsSavedAsAWidgetWithItsWidgets() throws {
        var layout = layout()
        let stacked = layout.stack(music.id, onto: weather.id)
        let id = try #require(stacked)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(HomeScreenLayout.self, from: data)
        #expect(decoded == layout)
        #expect(decoded.stack(for: id)?.smartRotate == true)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let first = (object?["pages"] as? [[[String: Any]]])?.first?.first
        #expect(first?["kind"] as? String == "widget")
        #expect(first?["targetID"] as? String == "audio.nowplaying")
        #expect(first?["stack"] != nil)
    }

    @Test func aDebugStackTakesThePlaceOfItsWidgets() throws {
        var layout = layout()
        let stack = try #require(HomeScreenItem.stack(.of(["personal.weather", "kitchen.timers"]), size: .medium, instance: "debug.0"))
        layout.placeFirst([stack])
        #expect(layout.pages[0].map(\.id) == ["stack:debug.0", "app:home", music.id])
    }
}

/// Which widget a dragged one would join as a stack.
@Suite struct HomeStackPlannerTests {
    private typealias Item = HomeReorderPlanner.Item
    private typealias Target = HomeReorderPlanner.Target

    /// 100 point cells with no gaps.
    private func frame(_ placement: GridPlacement) -> CGRect {
        CGRect(x: placement.column * 100, y: placement.row * 100,
               width: placement.span.columns * 100, height: placement.span.rows * 100)
    }

    private let medium = GridSpan(.medium)

    @Test func aWidgetOverOneOfItsSizeWouldStack() throws {
        // Two medium widgets side by side on a four by two grid, an icon and a small widget under them.
        let pages = [[Item(id: "a", span: medium, stackCount: 1), Item(id: "b", span: medium, stackCount: 2),
                      Item(id: "icon", span: .one), Item(id: "small", span: .one, stackCount: 1)]]
        let planner = HomeReorderPlanner(pages: pages, columns: 4, rows: 2)
        let origin = try #require(planner.origin(of: "a"))
        func under(_ point: CGPoint, moving id: String = "a") -> String? {
            planner.stackTarget(moving: id, center: point, onDrawnPage: 0, current: origin, frame: frame)
        }
        #expect(under(CGPoint(x: 300, y: 50)) == "b")
        #expect(under(CGPoint(x: 50, y: 150)) == nil, "an icon is not a stack")
        #expect(under(CGPoint(x: 150, y: 150)) == nil, "a small widget is not a medium one")
        #expect(under(CGPoint(x: 100, y: 50)) == nil, "over its own slot nothing stacks")
        #expect(under(CGPoint(x: 300, y: 50), moving: "icon") == nil, "an icon never stacks")
        // Once stacked, the stack sits where the target sat, under its new ID.
        let stacked = planner.stacking("a", onto: "b", as: "stack:b")
        #expect(stacked.pages[0].map(\.id) == ["stack:b", "icon", "small"])
        #expect(stacked.pages[0][0].stackCount == 3)
        let slot = try #require(stacked.origin(of: "stack:b").flatMap { stacked.slot(of: "stack:b", at: $0) })
        #expect(slot.page == 0 && slot.placement.column == 0 && slot.placement.row == 0)
    }

    @Test func aFullStackTakesNoMore() throws {
        let pages = [[Item(id: "a", span: medium, stackCount: 2), Item(id: "b", span: medium, stackCount: WidgetStack.maxMembers - 1)]]
        let planner = HomeReorderPlanner(pages: pages, columns: 4, rows: 2)
        let origin = try #require(planner.origin(of: "a"))
        #expect(planner.stackTarget(moving: "a", center: CGPoint(x: 300, y: 50), onDrawnPage: 0, current: origin,
                                    frame: frame) == nil)
    }
}
