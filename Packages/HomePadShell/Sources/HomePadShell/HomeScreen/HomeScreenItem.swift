import Foundation
import HomePadCore

/// One thing on a Home Screen page: an app icon, a widget at a size, or a
/// widget stack at a size.
struct HomeScreenItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case app, widget
    }

    var kind: Kind
    /// The app or widget descriptor ID. For a stack, its first widget's.
    var targetID: String
    /// `WidgetSize` raw value, for widgets.
    var size: String?
    /// Tells copies of one widget apart. A widget added from the gallery gets
    /// one, so a widget with settings can be added again: two Reminders
    /// widgets on two lists. Nil for apps, and for widgets placed before
    /// copies could be added, which keep the ID they had.
    var instance: String? = nil
    /// The widget's own settings, as Edit Widget changes them. Nil until one
    /// changes. For a stack, its first widget's.
    var settings: WidgetSettings? = nil
    /// The widgets of a stack (`WidgetStack`), nil for a single widget. A
    /// stack keeps `.widget` as its kind and its first widget in `targetID`
    /// and `settings`, so a HomePad from before stacks shows that widget in
    /// its place rather than losing the layout.
    var stack: WidgetStack? = nil

    /// Unique on a Home Screen: each app appears once, each widget once per copy, and each stack once.
    var id: String {
        if stack != nil, let instance { return "stack:\(instance)" }
        guard let instance else { return "\(kind.rawValue):\(targetID)" }
        return "\(kind.rawValue):\(targetID):\(instance)"
    }

    static func app(_ id: String) -> HomeScreenItem {
        HomeScreenItem(kind: .app, targetID: id, size: nil)
    }

    static func widget(_ id: String, size: WidgetSize) -> HomeScreenItem {
        HomeScreenItem(kind: .widget, targetID: id, size: size.rawValue)
    }

    /// A new copy of a widget, with an ID of its own.
    static func newWidget(_ id: String, size: WidgetSize) -> HomeScreenItem {
        HomeScreenItem(kind: .widget, targetID: id, size: size.rawValue, instance: UUID().uuidString)
    }

    /// A stack of widgets at a size. A stack of one is that widget.
    static func stack(_ stack: WidgetStack, size: WidgetSize, instance: String = UUID().uuidString) -> HomeScreenItem? {
        var item = HomeScreenItem(kind: .widget, targetID: "", size: size.rawValue, instance: instance)
        return item.settingStack(stack) ? item : nil
    }

    var widgetSize: WidgetSize {
        size.flatMap(WidgetSize.init(rawValue:)) ?? .small
    }

    var span: GridSpan {
        kind == .app ? .one : GridSpan(widgetSize)
    }

    /// True for a widget stack.
    var isStack: Bool { stack != nil }

    /// The widgets this item stands for: a stack's, or a single widget as a
    /// stack of one, keeping its settings and copy. Empty for an app.
    var stackMembers: [WidgetStack.Member] {
        guard kind == .widget else { return [] }
        if let stack { return stack.members }
        return [WidgetStack.Member(id: instance ?? UUID().uuidString, widgetID: targetID, settings: settings)]
    }

    /// Makes the item hold these widgets: a stack while there are two or more,
    /// the widget itself for one, keeping its settings and copy. False for
    /// none, when the item should go.
    @discardableResult
    mutating func settingStack(_ stack: WidgetStack) -> Bool {
        guard kind == .widget, let first = stack.members.first else { return false }
        targetID = first.widgetID
        settings = first.settings
        if stack.members.count > 1 {
            self.stack = stack
            if instance == nil { instance = UUID().uuidString }
        } else {
            self.stack = nil
            instance = first.id
        }
        return true
    }
}
