import CoreGraphics
import Foundation
import HomePadCore

/// A widget where it sits on a face's grid now.
struct FaceGridItem: Hashable, Sendable, Identifiable {
    var id: UUID
    var widgetID: String
    var size: WidgetSize
    var area: FaceGridArea
}

/// The widgets on one face's grid in one orientation, and the rules for
/// changing them: no widget covers another or the face's own content
/// (`FaceGrid.blocked`), and every change keeps it that way.
///
/// Moving or resizing a widget onto others pushes them aside, as on iPadOS:
/// each one it covers goes to the nearest free area it fits. When one has
/// nowhere to go, the change is refused and nothing moves. Every change works
/// from the board as it was, so a drag can try spot after spot and always
/// shows the same result for the same spot.
struct FaceWidgetBoard: Equatable, Sendable {
    let grid: FaceGrid
    /// Where widgets with no cell of their own go first.
    let fill: FaceGridFill
    /// The widgets on the grid, in saved order.
    private(set) var items: [FaceGridItem]
    /// Saved widgets with no room on this grid, or whose module is gone. They
    /// stay saved, so nobody's choice is lost, and return when there is room.
    private(set) var leftOut: [FaceWidgetPlacement]

    init(grid: FaceGrid, fill: FaceGridFill = .readingOrder, items: [FaceGridItem] = [],
         leftOut: [FaceWidgetPlacement] = []) {
        self.grid = grid
        self.fill = fill
        self.items = items
        self.leftOut = leftOut
    }

    /// Arranges saved placements on a grid. A widget placed by hand keeps its
    /// cell while that area is open and no earlier widget took it. Of the
    /// rest, those anchored top leading (`WidgetAnchor`) each take the free
    /// area nearest the grid's top leading corner, and the others go together,
    /// in saved order, into the narrowest band along the fill's edge that
    /// holds them all (`FaceGridFill`). When no band does, each in turn takes
    /// the first free area, at its own size or, when that has no room, the
    /// largest smaller size it supports.
    ///
    /// - Parameter sizes: The sizes a widget supports. Empty for a widget whose module is gone.
    /// - Parameter stackSizes: The sizes a stack takes, by placement: those all its
    ///   widgets support. Nil for a placement that is not a stack.
    /// - Parameter anchors: Where a widget without a cell lands.
    init(placements: [FaceWidgetPlacement], grid: FaceGrid, fill: FaceGridFill,
         sizes: (String) -> [WidgetSize] = { _ in WidgetSize.allCases },
         stackSizes: (UUID) -> [WidgetSize]? = { _ in nil },
         anchors: (String) -> WidgetAnchor = { _ in .faceFill }) {
        self.grid = grid
        self.fill = fill
        func supported(_ placement: FaceWidgetPlacement) -> [WidgetSize] {
            stackSizes(placement.id) ?? sizes(placement.widgetID)
        }
        var placed: [UUID: FaceGridItem] = [:]
        var taken = Set<FaceGridCell>()
        var waiting: [FaceWidgetPlacement] = []

        for placement in placements {
            let allowed = supported(placement)
            guard !allowed.isEmpty else { continue }
            let size = Self.nearest(placement.size, in: allowed)
            if let cell = placement.cell {
                let area = FaceGridArea(origin: cell, size: size)
                if grid.isOpen(area), !area.cells.contains(where: taken.contains) {
                    placed[placement.id] = FaceGridItem(id: placement.id, widgetID: placement.widgetID, size: size, area: area)
                    taken.formUnion(area.cells)
                    continue
                }
            }
            waiting.append(placement)
        }
        // Anchored widgets first, so a glance gets its corner before the others fill their edge.
        let anchored = waiting.filter { anchors($0.widgetID) == .topLeading }
        waiting.removeAll { anchors($0.widgetID) == .topLeading }
        for placement in anchored {
            for size in Self.stepsDown(from: placement.size, in: supported(placement)) {
                guard let area = Self.nearestTopLeading(size, grid: grid, taken: taken) else { continue }
                placed[placement.id] = FaceGridItem(id: placement.id, widgetID: placement.widgetID, size: size, area: area)
                taken.formUnion(area.cells)
                break
            }
        }
        let group = waiting.map { (id: $0.id, size: Self.nearest($0.size, in: supported($0))) }
        if let areas = Self.placeTogether(group, grid: grid, fill: fill, taken: taken) {
            for (placement, member) in zip(waiting, group) {
                guard let area = areas[member.id] else { continue }
                placed[placement.id] = FaceGridItem(id: placement.id, widgetID: placement.widgetID, size: member.size, area: area)
            }
        } else {
            for placement in waiting {
                for size in Self.stepsDown(from: placement.size, in: supported(placement)) {
                    guard let area = Self.firstFree(size, grid: grid, fill: fill, taken: taken) else { continue }
                    placed[placement.id] = FaceGridItem(id: placement.id, widgetID: placement.widgetID, size: size, area: area)
                    taken.formUnion(area.cells)
                    break
                }
            }
        }
        items = placements.compactMap { placed[$0.id] }
        leftOut = placements.filter { placed[$0.id] == nil }
    }

    /// The arrangement to save: every widget pinned to its cell, then the
    /// widgets left out, as they were saved.
    var placements: [FaceWidgetPlacement] {
        items.map { FaceWidgetPlacement(id: $0.id, widgetID: $0.widgetID, size: $0.size, cell: $0.area.origin) } + leftOut
    }

    func item(_ id: UUID) -> FaceGridItem? {
        items.first { $0.id == id }
    }

    // MARK: Room

    /// True when the area is open on the grid and no widget covers it, other than those in `ignoring`.
    func isFree(_ area: FaceGridArea, ignoring: Set<UUID> = []) -> Bool {
        grid.isOpen(area) && !items.contains { !ignoring.contains($0.id) && $0.area.intersects(area) }
    }

    /// Where a new widget of `size` goes: the first free area, in reading
    /// order, in the narrowest band along the fill's edge (`FaceGridFill`).
    /// A widget anchored top leading takes the free area nearest the grid's
    /// top leading corner instead, wherever the face's content leaves one.
    func firstFreeArea(for size: WidgetSize, anchor: WidgetAnchor = .faceFill) -> FaceGridArea? {
        let taken = Set(items.flatMap(\.area.cells))
        switch anchor {
        case .faceFill: return Self.firstFree(size, grid: grid, fill: fill, taken: taken)
        case .topLeading: return Self.nearestTopLeading(size, grid: grid, taken: taken)
        }
    }

    /// True when a new widget of `size` has room.
    func hasRoom(for size: WidgetSize) -> Bool {
        firstFreeArea(for: size) != nil
    }

    // MARK: Changes

    /// Adds a widget in the first free area for its anchor, or returns nil when there is no room for it.
    func adding(_ widgetID: String, size: WidgetSize, id: UUID = UUID(), anchor: WidgetAnchor = .faceFill) -> FaceWidgetBoard? {
        guard let area = firstFreeArea(for: size, anchor: anchor) else { return nil }
        var board = self
        board.items.append(FaceGridItem(id: id, widgetID: widgetID, size: size, area: area))
        return board
    }

    /// Takes a widget off the face.
    func removing(_ id: UUID) -> FaceWidgetBoard {
        var board = self
        board.items.removeAll { $0.id == id }
        return board
    }

    /// Moves a widget's top leading corner to `origin`, pushing aside the
    /// widgets it lands on. Nil when it would leave the grid or cover the
    /// face's content, or when a widget it covers has nowhere to go.
    func moving(_ id: UUID, to origin: FaceGridCell) -> FaceWidgetBoard? {
        guard var item = item(id) else { return nil }
        if item.area.origin == origin { return self }
        item.area = item.area.moved(to: origin)
        return placing(item)
    }

    /// Changes a widget's size. It keeps its top leading cell when it can,
    /// otherwise it grows up or toward the leading edge just enough to fit,
    /// and pushes aside the widgets it then covers. Nil when no way fits.
    func resizing(_ id: UUID, to size: WidgetSize) -> FaceWidgetBoard? {
        guard let item = item(id) else { return nil }
        if item.size == size { return self }
        let shifts = (0..<size.rows).flatMap { up in (0..<size.columns).map { back in (back, up) } }
            .sorted { ($0.0 + $0.1, $0.1) < ($1.0 + $1.1, $1.1) }
        for (back, up) in shifts {
            var resized = item
            resized.size = size
            resized.area = FaceGridArea(column: item.area.column - back, row: item.area.row - up,
                                        columns: size.columns, rows: size.rows)
            if let board = placing(resized) { return board }
        }
        return nil
    }

    // MARK: Dragging

    /// Where a dragged widget lands with its center at `center`, in the face's
    /// coordinates: the top leading cell of the nearest area it can take,
    /// pushing others aside if it must. The area it is over now holds until
    /// another is nearer by a quarter of a cell, so a widget resting on the
    /// line between two areas does not flicker. Over the face's clock it
    /// lands in the nearest open area beside it.
    func dropOrigin(for id: UUID, center: CGPoint, current: FaceGridCell?) -> FaceGridCell? {
        guard let item = item(id) else { return nil }
        let candidates = grid.openAreas(for: item.size)
            .filter { moving(id, to: $0.origin) != nil }
            .map { (origin: $0.origin, distance: Self.distance(grid.frame(for: $0), center)) }
        guard let best = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
        if let current, let held = candidates.first(where: { $0.origin == current }),
           held.distance <= best.distance + hysteresis {
            return current
        }
        return best.origin
    }

    /// The size a widget being resized snaps to with its resize handle at
    /// `corner`, in the face's coordinates: of the sizes it supports and has
    /// room for, the one whose bottom trailing corner is nearest. The size
    /// shown now holds until another is nearer by a quarter of a cell.
    func resizeTarget(for id: UUID, corner: CGPoint, sizes: [WidgetSize], current: WidgetSize) -> WidgetSize {
        guard item(id) != nil else { return current }
        let candidates = sizes.compactMap { size -> (size: WidgetSize, distance: CGFloat)? in
            guard let area = resizing(id, to: size)?.item(id)?.area else { return nil }
            let frame = grid.frame(for: area)
            return (size, hypot(frame.maxX - corner.x, frame.maxY - corner.y))
        }
        guard let best = candidates.min(by: { $0.distance < $1.distance }) else { return current }
        if let held = candidates.first(where: { $0.size == current }), held.distance <= best.distance + hysteresis {
            return current
        }
        return best.size
    }

    /// Points another spot must be nearer by before a dragged widget leaves its own.
    var hysteresis: CGFloat {
        min(grid.cellSize.width, grid.cellSize.height) / 4
    }

    // MARK: Pushing aside

    /// Puts `moved`, already at its new area and size, on the board. Each
    /// widget it covers moves to the free area nearest where it was, in
    /// reading order. Nil when the area is not open or one has nowhere to go.
    private func placing(_ moved: FaceGridItem) -> FaceWidgetBoard? {
        guard grid.isOpen(moved.area) else { return nil }
        var taken = Set(moved.area.cells)
        var result: [UUID: FaceGridItem] = [moved.id: moved]
        var covered: [FaceGridItem] = []
        for other in items where other.id != moved.id {
            if other.area.intersects(moved.area) {
                covered.append(other)
            } else {
                result[other.id] = other
                taken.formUnion(other.area.cells)
            }
        }
        for other in covered.sorted(by: { ($0.area.row, $0.area.column) < ($1.area.row, $1.area.column) }) {
            guard let area = nearestFree(other.size, to: other.area, taken: taken) else { return nil }
            var pushed = other
            pushed.area = area
            result[other.id] = pushed
            taken.formUnion(area.cells)
        }
        var board = self
        board.items = items.map { result[$0.id] ?? $0 }
        return board
    }

    /// The free area for a widget of `size` whose center is nearest `area`'s. Ties go in reading order.
    private func nearestFree(_ size: WidgetSize, to area: FaceGridArea, taken: Set<FaceGridCell>) -> FaceGridArea? {
        let center = grid.frame(for: area)
        let target = CGPoint(x: center.midX, y: center.midY)
        return grid.openAreas(for: size)
            .filter { !$0.cells.contains(where: taken.contains) }
            .min { Self.distance(grid.frame(for: $0), target) < Self.distance(grid.frame(for: $1), target) }
    }

    /// Where one widget of `size` goes with `taken` cells in use: the first
    /// free area, in reading order, in the narrowest band along the fill's edge.
    private static func firstFree(_ size: WidgetSize, grid: FaceGrid, fill: FaceGridFill,
                                  taken: Set<FaceGridCell>) -> FaceGridArea? {
        let probe = UUID()
        return placeTogether([(probe, size)], grid: grid, fill: fill, taken: taken)?[probe]
    }

    /// The free area for a widget of `size` whose top leading corner is
    /// nearest the grid's own. Ties go in reading order, so a face whose
    /// content fills its top left puts it beside the content before below it.
    private static func nearestTopLeading(_ size: WidgetSize, grid: FaceGrid, taken: Set<FaceGridCell>) -> FaceGridArea? {
        let corner = grid.content.origin
        func distance(_ area: FaceGridArea) -> CGFloat {
            let frame = grid.frame(for: area)
            return hypot(frame.minX - corner.x, frame.minY - corner.y)
        }
        // `openAreas` lists areas in reading order and `min` keeps the first of equals.
        return grid.openAreas(for: size)
            .filter { !$0.cells.contains(where: taken.contains) }
            .min { distance($0) < distance($1) }
    }

    /// Areas for a group of widgets, each at its size, in reading order inside
    /// the narrowest band along the fill's edge that holds them all, so the
    /// group keeps its order and sits against that edge. Nil when no band does.
    private static func placeTogether(_ group: [(id: UUID, size: WidgetSize)], grid: FaceGrid, fill: FaceGridFill,
                                      taken: Set<FaceGridCell>) -> [UUID: FaceGridArea]? {
        guard !group.isEmpty else { return [:] }
        var open: [WidgetSize: [FaceGridArea]] = [:]
        for size in Set(group.map(\.size)) { open[size] = grid.openAreas(for: size) }
        for band in fill.bands(columns: grid.columns, rows: grid.rows) {
            var occupied = taken
            var areas: [UUID: FaceGridArea] = [:]
            for member in group {
                guard let area = open[member.size]?.first(where: {
                    band.contains($0) && !$0.cells.contains(where: occupied.contains)
                }) else { break }
                areas[member.id] = area
                occupied.formUnion(area.cells)
            }
            if areas.count == group.count { return areas }
        }
        return nil
    }

    private static func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    // MARK: Sizes

    /// `size` when supported, else the nearest supported size, smaller first.
    static func nearest(_ size: WidgetSize, in supported: [WidgetSize]) -> WidgetSize {
        if supported.contains(size) { return size }
        return stepsDown(from: size, in: supported).first ?? supported.first ?? size
    }

    /// The sizes to try for a widget with no room at `size`: that size, then
    /// each smaller one it supports, largest first. A widget with no size
    /// that small tries its own sizes, smallest first.
    static func stepsDown(from size: WidgetSize, in supported: [WidgetSize]) -> [WidgetSize] {
        let rank = WidgetSize.largestFirst.firstIndex(of: size) ?? 0
        let smaller = WidgetSize.largestFirst.enumerated()
            .filter { $0.offset >= rank && supported.contains($0.element) }
            .map(\.element)
        if !smaller.isEmpty { return smaller }
        return WidgetSize.largestFirst.reversed().filter(supported.contains)
    }
}
