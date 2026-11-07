import HomePadCore

/// An item on screen with what it resolved to.
struct HomeTile: Identifiable {
    enum Content {
        case app(AppDescriptor)
        case widget(WidgetDescriptor, WidgetSize)
        /// A widget stack: its widgets that show, in order, at the stack's size.
        case stack([StackMember], WidgetSize)
    }

    /// One widget of a stack as it shows here.
    struct StackMember {
        let member: WidgetStack.Member
        let widget: WidgetDescriptor
        /// Personal and not unlocked: drawn with a lock, and Smart Rotate skips it.
        let isLocked: Bool
    }

    let item: HomeScreenItem
    let content: Content
    /// Personal and not unlocked: drawn with a lock.
    let isLocked: Bool
    var id: String { item.id }

    var span: GridSpan {
        switch content {
        case .app: .one
        case .widget(_, let size), .stack(_, let size): GridSpan(size)
        }
    }

    /// How many widgets it stands for, when it can join a stack: one for a
    /// widget, its count for a stack, nil for an app.
    var stackCount: Int? {
        switch content {
        case .app: nil
        case .widget: 1
        case .stack: item.stack?.members.count ?? 1
        }
    }
}

/// One screen-sized page as drawn. A logical page that overflows the grid
/// renders as several of these.
struct RenderedHomePage: Identifiable {
    let index: Int
    /// The layout page that edits on this page apply to.
    let logicalPage: Int
    let tiles: [(tile: HomeTile, placement: GridPlacement)]
    var id: Int { index }
}

/// Turns a stored layout into pages to draw: drops items whose module is not
/// installed, hides or locks personal items, and packs each page into the grid.
@MainActor
enum HomeScreenPages {
    static func render(
        _ layout: HomeScreenLayout, registry: ModuleRegistry, access: PersonalAccess, metrics: HomeGridMetrics
    ) -> [RenderedHomePage] {
        var rendered: [RenderedHomePage] = []
        for (logicalPage, items) in layout.pages.enumerated() {
            let tiles = items.compactMap { resolve($0, registry: registry, access: access) }
            let pages = GridPacker.paginate(tiles.map(\.span), columns: metrics.columns, rows: metrics.rows)
            for placements in pages {
                let placed = placements.map { (tiles[$0.index], $0) }
                rendered.append(RenderedHomePage(index: rendered.count, logicalPage: logicalPage, tiles: placed))
            }
        }
        return rendered.isEmpty ? [RenderedHomePage(index: 0, logicalPage: 0, tiles: [])] : rendered
    }

    /// Each logical page's items that show, in order, for planning a reorder.
    /// Empty and fully hidden pages stay in place, so page numbers match the layout's.
    static func shownItems(
        _ layout: HomeScreenLayout, registry: ModuleRegistry, access: PersonalAccess
    ) -> [[HomeReorderPlanner.Item]] {
        layout.pages.map { items in
            items.compactMap { resolve($0, registry: registry, access: access) }
                .map { HomeReorderPlanner.Item(id: $0.id, span: $0.span, stackCount: $0.stackCount) }
        }
    }

    static func resolve(_ item: HomeScreenItem, registry: ModuleRegistry, access: PersonalAccess) -> HomeTile? {
        switch item.kind {
        case .app:
            guard let app = registry.app(item.targetID) else { return nil }
            let visibility = access.visibility(isPersonal: app.requiresRecognizedMember)
            guard visibility != .hidden else { return nil }
            return HomeTile(item: item, content: .app(app), isLocked: visibility == .locked)
        case .widget:
            if let stack = item.stack {
                return resolveStack(stack, item: item, registry: registry, access: access)
            }
            guard let widget = registry.widget(item.targetID) else { return nil }
            let visibility = access.visibility(isPersonal: widget.isPersonal)
            guard visibility != .hidden else { return nil }
            let size = widget.supportedSizes.contains(item.widgetSize) ? item.widgetSize : (widget.supportedSizes.first ?? .small)
            return HomeTile(item: item, content: .widget(widget, size), isLocked: visibility == .locked)
        }
    }

    /// A stack shows the widgets this person may see whose module is
    /// installed, at its size. The others stay saved and come back. With none
    /// left to show the stack is left out, as a hidden widget is.
    private static func resolveStack(_ stack: WidgetStack, item: HomeScreenItem, registry: ModuleRegistry,
                                     access: PersonalAccess) -> HomeTile? {
        let members = stack.members.compactMap { member -> HomeTile.StackMember? in
            guard let widget = registry.widget(member.widgetID) else { return nil }
            let visibility = access.visibility(isPersonal: widget.isPersonal)
            guard visibility != .hidden else { return nil }
            return HomeTile.StackMember(member: member, widget: widget, isLocked: visibility == .locked)
        }
        guard !members.isEmpty else { return nil }
        return HomeTile(item: item, content: .stack(members, item.widgetSize), isLocked: members.allSatisfy(\.isLocked))
    }
}
