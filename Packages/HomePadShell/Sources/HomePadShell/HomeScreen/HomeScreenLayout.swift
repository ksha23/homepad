import HomePadCore

/// One person's Home Screen: pages of apps and widgets in their chosen order.
/// Pages are logical. When a page holds more than fits on screen, the
/// renderer continues it on the next visible page.
struct HomeScreenLayout: Codable, Equatable, Sendable {
    var pages: [[HomeScreenItem]]
    /// Every app that has been placed at least once. Apps the user removed stay
    /// listed, so they are not added back automatically. New apps are.
    var knownAppIDs: Set<String>
    /// The mini widget right of the header's lines: the glance, small, until
    /// the member changes it, and nil once they remove it. Layouts saved
    /// before mini widgets kept the glance under `glance` (see `init(from:)`).
    var miniWidget: MiniWidgetPlacement? = GlanceMiniWidget.headerDefault

    /// Widgets on a fresh Home Screen, in order, with their size.
    static let defaultWidgets: [(id: String, size: WidgetSize)] = [
        ("smarthome.favorites", .large),
        ("personal.weather", .medium),
        ("personal.upnext", .medium),
        ("audio.nowplaying", .medium),
        ("smarthome.scenes", .medium),
    ]

    /// Apps that come first on a fresh Home Screen. Everything else follows.
    static let leadingApps = ["home", "cameras", "assistant", "music", "calendar", "reminders",
                              "timers", "recipes", "weather", "photos", "intercom", "dashboards"]

    /// A layout that looks good with no setup: one logical page of big widgets
    /// and the most useful apps, interleaved so the grid packs densely. The
    /// renderer flows whatever does not fit onto further pages, so the first
    /// page is full on every iPad size and orientation.
    static func makeDefault(appIDs: [String], widgets: [(id: String, sizes: [WidgetSize])]) -> HomeScreenLayout {
        let ordered = leadingApps.filter(appIDs.contains) + appIDs.filter { !leadingApps.contains($0) }
        var apps = ordered.map(HomeScreenItem.app)[...]
        let available = Dictionary(widgets.map { ($0.id, $0.sizes) }, uniquingKeysWith: { first, _ in first })
        var chosen = defaultWidgets.compactMap { entry -> HomeScreenItem? in
            guard let sizes = available[entry.id] else { return nil }
            return .widget(entry.id, size: sizes.contains(entry.size) ? entry.size : preferredSize(sizes, first: false))
        }[...]
        if chosen.isEmpty, let first = widgets.first {
            chosen = [.widget(first.id, size: preferredSize(first.sizes, first: true))]
        }
        // Large widget and two mediums, four apps, two mediums, then the rest.
        var page: [HomeScreenItem] = []
        page += chosen.prefix(3); chosen = chosen.dropFirst(3)
        page += apps.prefix(4); apps = apps.dropFirst(4)
        page += chosen.prefix(2); chosen = chosen.dropFirst(2)
        page += apps + chosen
        return HomeScreenLayout(pages: [page], knownAppIDs: Set(appIDs))
    }

    /// The layout with newly registered apps appended to the last page.
    func reconciled(withAppIDs appIDs: [String]) -> HomeScreenLayout {
        let newIDs = appIDs.filter { !knownAppIDs.contains($0) }
        guard !newIDs.isEmpty else { return self }
        var copy = self
        if copy.pages.isEmpty { copy.pages = [[]] }
        copy.pages[copy.pages.count - 1].append(contentsOf: newIDs.map(HomeScreenItem.app))
        copy.knownAppIDs.formUnion(newIDs)
        return copy
    }

    var allItems: [HomeScreenItem] { pages.flatMap { $0 } }

    func contains(_ itemID: String) -> Bool {
        allItems.contains { $0.id == itemID }
    }

    /// True when a copy of this widget is on the Home Screen, on its own or in a stack.
    func containsWidget(_ widgetID: String) -> Bool {
        allItems.contains { $0.stackMembers.contains { $0.widgetID == widgetID } }
    }

    // MARK: Widget settings

    /// A widget's own settings (Edit Widget), empty when none changed.
    func settings(for itemID: String) -> WidgetSettings {
        allItems.first { $0.id == itemID }?.settings ?? WidgetSettings()
    }

    /// Saves a widget's settings with its place, so they move with it and go
    /// when it is removed.
    mutating func setSettings(_ settings: WidgetSettings, for itemID: String) {
        for page in pages.indices {
            if let index = pages[page].firstIndex(where: { $0.id == itemID && $0.kind == .widget }) {
                pages[page][index].settings = settings.isEmpty ? nil : settings
            }
        }
    }

    // MARK: Stacks

    /// The stack an item holds, nil for a single widget or an app.
    func stack(for itemID: String) -> WidgetStack? {
        allItems.first { $0.id == itemID }?.stack
    }

    /// Changes a stack's widgets in its place. Two or more stay a stack, one
    /// left becomes that widget, with its settings, and none takes it off.
    mutating func setStack(_ stack: WidgetStack, for itemID: String) {
        for page in pages.indices {
            guard let index = pages[page].firstIndex(where: { $0.id == itemID && $0.kind == .widget }) else { continue }
            if !pages[page][index].settingStack(stack) { pages[page].remove(at: index) }
        }
    }

    /// True when the item `draggedID` can join `targetID` as a stack, as
    /// dropping a widget on another does on iPadOS: both widgets or stacks of
    /// one size, with room for all their widgets.
    func canStack(_ draggedID: String, onto targetID: String) -> Bool {
        guard draggedID != targetID, let dragged = allItems.first(where: { $0.id == draggedID }),
              let target = allItems.first(where: { $0.id == targetID }),
              dragged.kind == .widget, target.kind == .widget, dragged.widgetSize == target.widgetSize else { return false }
        return dragged.stackMembers.count + target.stackMembers.count <= WidgetStack.maxMembers
    }

    /// Drops a widget or stack onto another of the same size: they become one
    /// stack in the target's place, the dropped widgets on top, and the
    /// target's Smart Rotate choice kept. Returns the stack's ID, or nil when
    /// they cannot stack (`canStack`).
    @discardableResult
    mutating func stack(_ draggedID: String, onto targetID: String) -> String? {
        guard canStack(draggedID, onto: targetID), let dragged = allItems.first(where: { $0.id == draggedID }) else { return nil }
        for page in pages.indices {
            guard let index = pages[page].firstIndex(where: { $0.id == targetID }) else { continue }
            var target = pages[page][index]
            var stack = target.stack ?? WidgetStack(members: target.stackMembers)
            stack.putOnTop(dragged.stackMembers)
            target.settingStack(stack)
            pages[page][index] = target
            remove(draggedID)
            return target.id
        }
        return nil
    }

    // MARK: Editing

    mutating func remove(_ itemID: String) {
        for index in pages.indices {
            pages[index].removeAll { $0.id == itemID }
        }
    }

    /// Moves an item so it sits right before `targetID`, possibly on another page.
    mutating func move(_ itemID: String, before targetID: String) {
        guard itemID != targetID, let item = allItems.first(where: { $0.id == itemID }) else { return }
        remove(itemID)
        for page in pages.indices {
            if let index = pages[page].firstIndex(where: { $0.id == targetID }) {
                pages[page].insert(item, at: index)
                return
            }
        }
        pages[pages.count - 1].append(item)
    }

    /// Moves an item to the end of a page.
    mutating func move(_ itemID: String, toEndOfPage page: Int) {
        guard let item = allItems.first(where: { $0.id == itemID }) else { return }
        remove(itemID)
        add(item, toPage: page)
    }

    /// Moves an item onto a page, right before `targetID`, or to the page's end when it is nil.
    /// A live reorder on the Home Screen saves its drop with this.
    mutating func move(_ itemID: String, toPage page: Int, before targetID: String?) {
        if let targetID {
            move(itemID, before: targetID)
        } else {
            move(itemID, toEndOfPage: page)
        }
    }

    /// Adds an item to the end of a page (or the last page). Already present items are left alone.
    mutating func add(_ item: HomeScreenItem, toPage page: Int) {
        guard !contains(item.id) else { return }
        if pages.isEmpty { pages = [[]] }
        let target = min(max(page, 0), pages.count - 1)
        pages[target].append(item)
        if item.kind == .app { knownAppIDs.insert(item.targetID) }
    }

    /// Moves these items, in order, to the start of the first page, adding any
    /// that are missing. A stack takes the place of the single widgets it holds,
    /// so none shows twice.
    mutating func placeFirst(_ items: [HomeScreenItem]) {
        for item in items {
            remove(item.id)
            for member in item.stack?.members ?? [] { remove(HomeScreenItem.widget(member.widgetID, size: .small).id) }
        }
        if pages.isEmpty { pages = [[]] }
        pages[0].insert(contentsOf: items, at: 0)
    }

    mutating func resize(_ itemID: String, to size: WidgetSize) {
        for page in pages.indices {
            if let index = pages[page].firstIndex(where: { $0.id == itemID && $0.kind == .widget }) {
                pages[page][index].size = size.rawValue
            }
        }
    }

    /// Puts a mini widget in the header, changes its size, or removes it (nil).
    mutating func setMiniWidget(_ miniWidget: MiniWidgetPlacement?) {
        self.miniWidget = miniWidget
    }

    mutating func appendPage() {
        pages.append([])
    }

    /// Drops one page if it is empty, but always keeps one page.
    mutating func removePageIfEmpty(_ page: Int) {
        guard pages.indices.contains(page), pages[page].isEmpty, pages.count > 1 else { return }
        pages.remove(at: page)
    }

    /// Drops empty pages but always keeps one.
    mutating func removeEmptyPages() {
        pages = pages.filter { !$0.isEmpty }.nonEmpty
    }

    private static func preferredSize(_ sizes: [WidgetSize], first: Bool) -> WidgetSize {
        let order: [WidgetSize] = first ? [.large, .medium, .small] : [.medium, .large, .small]
        return order.first { sizes.contains($0) } ?? .small
    }
}

extension HomeScreenLayout {
    private enum CodingKeys: String, CodingKey {
        case pages, knownAppIDs, miniWidget
        /// Before mini widgets: whether the glance showed and its size (`LegacyGlance`).
        case glance
    }

    /// The header glance as layouts saved it before mini widgets.
    private struct LegacyGlance: Decodable {
        var isShown = true
        var size: MiniWidgetSize = .small
    }

    /// Reads the header's mini widget. A layout saved before mini widgets
    /// keeps its glance and size, or its glance removed, and one saved before
    /// the glance shows the default. A removed mini widget is saved as null,
    /// so it stays removed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pages = try container.decode([[HomeScreenItem]].self, forKey: .pages)
        knownAppIDs = try container.decode(Set<String>.self, forKey: .knownAppIDs)
        if container.contains(.miniWidget) {
            miniWidget = try container.decodeIfPresent(MiniWidgetPlacement.self, forKey: .miniWidget)
        } else if let glance = try container.decodeIfPresent(LegacyGlance.self, forKey: .glance) {
            miniWidget = glance.isShown ? MiniWidgetPlacement(widgetID: GlanceMiniWidget.id, size: glance.size) : nil
        } else {
            miniWidget = GlanceMiniWidget.headerDefault
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
        // Sorted, so one layout always encodes the same and HomePads sharing it see no change where there is none.
        try container.encode(knownAppIDs.sorted(), forKey: .knownAppIDs)
        // Null rather than left out, so a removed mini widget does not come back as the default.
        if let miniWidget {
            try container.encode(miniWidget, forKey: .miniWidget)
        } else {
            try container.encodeNil(forKey: .miniWidget)
        }
    }
}

private extension Array where Element == [HomeScreenItem] {
    /// At least one (possibly empty) page.
    var nonEmpty: [[HomeScreenItem]] { isEmpty ? [[]] : self }
}
