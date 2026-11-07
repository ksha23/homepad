import Foundation
import HomePadCore

/// Debug only: `-HomePadFacesWidgets` puts widgets on the face on the wall
/// and on the face the editor opens, for screenshots.
///
///     -HomePadFacesWidgets "personal.weather:medium@4,0;kitchen.timers:small;personal.upnext:large"
///
/// Each widget is its ID, a colon and its size, then optionally an at sign
/// and the column and row of its top leading cell. Without a cell it takes
/// the first open area. The list is the landscape layout. A second list after
/// a bar (`|`) is the portrait layout. Without one, portrait reflows. IDs
/// joined by `+` make a stack of those widgets:
///
///     -HomePadFacesWidgets "personal.upnext+personal.weather+audio.nowplaying:medium@4,0"
///
/// `-HomePadFacesMiniWidget` puts a mini widget in the face's top left
/// corner, as its ID, a colon and its size, or `off` to take it away:
///
///     -HomePadFacesMiniWidget "shell.glance.mini:small"
extension FaceDebugOptions {
    /// The configuration with `-HomePadFacesWidgets` and `-HomePadFacesMiniWidget` applied.
    static func withWidgetOverride(_ configuration: FaceConfiguration) -> FaceConfiguration {
        #if DEBUG
        var configuration = configuration
        if let spec = UserDefaults.standard.string(forKey: "HomePadFacesWidgets"), let layout = widgetLayout(from: spec) {
            configuration.widgetLayout = layout
        }
        if let spec = UserDefaults.standard.string(forKey: "HomePadFacesMiniWidget") {
            configuration.miniWidget = miniWidget(from: spec)
        }
        return configuration
        #else
        return configuration
        #endif
    }

    /// The mini widget a `-HomePadFacesMiniWidget` value describes: "shell.glance.mini:medium",
    /// or the ID alone for small. Nil for `off`.
    static func miniWidget(from spec: String) -> MiniWidgetPlacement? {
        let parts = spec.split(separator: ":").map(String.init)
        guard let id = parts.first, !id.isEmpty, id != "off" else { return nil }
        let size = parts.count > 1 ? MiniWidgetSize(rawValue: parts[1]) ?? .small : .small
        return MiniWidgetPlacement(widgetID: id, size: size)
    }

    /// The layout a `-HomePadFacesWidgets` value describes, or nil when it describes none.
    static func widgetLayout(from spec: String) -> FaceWidgetLayout? {
        let lists = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let first = lists.first else { return nil }
        let landscapeEntries = entries(from: first, startingAt: 0)
        let portraitEntries = lists.count > 1 ? entries(from: lists[1], startingAt: landscapeEntries.count) : nil
        let landscape = landscapeEntries.map(\.placement)
        let portrait = portraitEntries?.map(\.placement)
        // The same widget in both lists shares its ID, so it is one widget in two places.
        let matched = portrait.map { list in
            list.map { placement in
                var placement = placement
                if let twin = landscape.first(where: { $0.widgetID == placement.widgetID }) { placement.id = twin.id }
                return placement
            }
        }
        guard !landscape.isEmpty || matched?.isEmpty == false else { return nil }
        // A stack keeps its widgets once, by its placement's ID, as a saved face does.
        // Portrait's under the ID it shares with its landscape twin.
        let placed = landscapeEntries.map { ($0.placement.id, $0.widgetIDs) }
            + zip(matched ?? [], portraitEntries ?? []).map { ($0.id, $1.widgetIDs) }
        var stacks: [String: WidgetStack] = [:]
        for (id, widgetIDs) in placed where widgetIDs.count > 1 {
            let members = widgetIDs.enumerated().map { index, widgetID in
                WidgetStack.Member(id: "\(id.uuidString).\(index)", widgetID: widgetID)
            }
            stacks[id.uuidString] = WidgetStack(members: members)
        }
        return FaceWidgetLayout(landscape: landscape, portrait: matched, stacks: stacks.isEmpty ? nil : stacks)
    }

    /// Each entry's placement, named for its first widget, with all its widgets: more than one for a stack.
    private static func entries(from list: String, startingAt first: Int) -> [(placement: FaceWidgetPlacement, widgetIDs: [String])] {
        list.split(separator: ";").enumerated().compactMap { index, entry in
            let parts = entry.split(separator: "@", maxSplits: 1)
            let head = parts[0].split(separator: ":")
            let ids = head.first.map { $0.split(separator: "+").map(String.init) } ?? []
            guard let id = ids.first, !id.isEmpty else { return nil }
            let size = head.count > 1 ? WidgetSize(rawValue: String(head[1])) ?? .small : .small
            let numbers = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Int($0) } : []
            let cell = numbers.count == 2 ? FaceGridCell(column: numbers[0], row: numbers[1]) : nil
            return (FaceWidgetPlacement(id: debugID(first + index), widgetID: id, size: size, cell: cell), ids)
        }
    }

    /// A fixed ID per position in the list, so a relaunch draws the same widgets.
    private static func debugID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "DEB00000-0000-4000-8000-%012d", index)) ?? UUID()
    }
}
