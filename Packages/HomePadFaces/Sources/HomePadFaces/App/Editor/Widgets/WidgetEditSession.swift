import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import Observation
import SwiftUI

/// The face editor's widgets page while someone arranges widgets on the
/// preview: which widget is selected (it shows its resize handle), and the
/// drag or resize under way.
///
/// Every gesture works from the board as it was when it began
/// (`FaceWidgetBoard`), so the others move aside at once as the widget
/// passes over them and move back when it leaves, and letting go saves the
/// board shown. Only the views that draw the lifted widget read
/// `translation`, so following the finger redraws nothing else.
@MainActor
@Observable
final class WidgetEditSession {
    /// A widget lifted and following the finger.
    struct Lift: Equatable {
        let id: UUID
        /// Where it sat when it lifted, in the face's coordinates.
        let frame: CGRect
    }

    /// The widget whose resize handle shows.
    var selection: UUID?
    private(set) var lift: Lift?
    /// True while the lifted widget is in the air: drawn larger, still, above the others.
    private(set) var isLifted = false
    /// How far the lifted widget has moved, in the face's coordinates.
    private(set) var translation: CGSize = .zero
    /// The widget being resized.
    private(set) var resizingID: UUID?
    /// The board as the gesture would leave it now, with the others pushed
    /// aside. Nil when nothing is moving.
    private(set) var working: FaceWidgetBoard?

    @ObservationIgnored private var base: FaceWidgetBoard?
    @ObservationIgnored private var target: FaceGridCell?
    /// Where the resize handle started, in the face's coordinates: the widget's bottom trailing corner.
    @ObservationIgnored private var startCorner: CGPoint = .zero
    /// Counts gestures, so a settle that finishes late never ends the next one.
    @ObservationIgnored private var generation = 0

    /// How much larger the lifted widget is drawn, as on the iPadOS Home Screen.
    static let liftScale: CGFloat = 1.06

    /// The board to draw: the gesture's, or the saved one.
    func board(saved: FaceWidgetBoard) -> FaceWidgetBoard {
        working ?? saved
    }

    // MARK: Moving

    /// Lifts a widget to move it.
    func beginDrag(_ id: UUID, on board: FaceWidgetBoard) {
        guard lift == nil, resizingID == nil, let item = board.item(id) else { return }
        generation += 1
        base = board
        working = board
        target = item.area.origin
        translation = .zero
        selection = id
        lift = Lift(id: id, frame: board.grid.frame(for: item.area))
        withAnimation(Theme.Motion.settle) { isLifted = true }
    }

    /// The finger moved by `translation`, in the face's coordinates: the
    /// widget follows it exactly and the others make room where it would land.
    func drag(by translation: CGSize) {
        guard let lift, let base else { return }
        self.translation = translation
        let center = CGPoint(x: lift.frame.midX + translation.width, y: lift.frame.midY + translation.height)
        guard let next = base.dropOrigin(for: lift.id, center: center, current: target), next != target,
              let moved = base.moving(lift.id, to: next) else { return }
        target = next
        withAnimation(Theme.Motion.settle) { working = moved }
    }

    /// The finger let go: returns the board to save, or nil when nothing
    /// moved, and the lifted widget settles into its place.
    func drop() -> FaceWidgetBoard? {
        guard let lift, let working, let item = working.item(lift.id) else {
            end()
            return nil
        }
        let changed = working != base
        let slot = working.grid.frame(for: item.area)
        let generation = generation
        withAnimation(Theme.Motion.settle, completionCriteria: .logicallyComplete) {
            isLifted = false
            translation = CGSize(width: slot.minX - lift.frame.minX, height: slot.minY - lift.frame.minY)
        } completion: { [weak self] in
            if self?.generation == generation { self?.end() }
        }
        return changed ? working : nil
    }

    // MARK: Resizing

    /// Starts dragging a widget's resize handle.
    func beginResize(_ id: UUID, on board: FaceWidgetBoard) {
        guard lift == nil, resizingID == nil, let item = board.item(id) else { return }
        generation += 1
        base = board
        working = board
        resizingID = id
        selection = id
        let frame = board.grid.frame(for: item.area)
        startCorner = CGPoint(x: frame.maxX, y: frame.maxY)
    }

    /// The handle moved by `translation`, in the face's coordinates: the
    /// widget snaps to the nearest size it supports and has room for.
    func resize(by translation: CGSize, sizes: [WidgetSize]) {
        guard let id = resizingID, let base, let working, let current = working.item(id)?.size else { return }
        let corner = CGPoint(x: startCorner.x + translation.width, y: startCorner.y + translation.height)
        let size = base.resizeTarget(for: id, corner: corner, sizes: sizes, current: current)
        guard size != current, let resized = base.resizing(id, to: size) else { return }
        withAnimation(Theme.Motion.settle) { self.working = resized }
    }

    /// The handle was let go: returns the board to save, or nil when the size did not change.
    func endResize() -> FaceWidgetBoard? {
        defer { end() }
        guard resizingID != nil, let working, working != base else { return nil }
        return working
    }

    /// True while a widget is moving or resizing.
    var isActive: Bool { lift != nil || resizingID != nil }

    /// The gesture ended some other way: everything goes back where it was.
    func cancel() {
        withAnimation(Theme.Motion.settle) { end() }
    }

    private func end() {
        lift = nil
        isLifted = false
        translation = .zero
        resizingID = nil
        working = nil
        base = nil
        target = nil
    }
}
