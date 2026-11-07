import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

@MainActor @Suite struct FaceEditorTests {
    // MARK: Preview distance

    /// A page for something that shows only up close. No face has one now
    /// (widgets show at every distance), but the editor keeps the rule.
    private static let upClose = FaceOption(id: "detail", title: "Detail", kind: .choices([]), previewDistance: .near)

    @Test func previewStartsAcrossTheRoom() {
        var state = EditorDistanceState()
        state.open(ModularFace.style)
        #expect(state.shown == .far)
    }

    @Test func aPageThatOnlyShowsUpCloseSwitchesToUpClose() {
        var state = EditorDistanceState()
        state.open(Self.upClose)
        #expect(state.shown == .near)
        // Back on a page that shows at both distances, the person's own pick returns.
        state.open(ModularFace.color)
        #expect(state.shown == .far)
    }

    @Test func aDistancePickedByHandHoldsOnOtherPages() {
        var state = EditorDistanceState()
        state.pick(.near)
        state.open(ModularFace.color)
        #expect(state.shown == .near)
        state.open(ModularFace.style)
        #expect(state.shown == .near)
    }

    @Test func thePersonCanStillFlipAnUpClosePage() {
        var state = EditorDistanceState()
        state.open(Self.upClose)
        state.pick(.far)
        #expect(state.shown == .far)
        // Opening the page again shows it at the distance it needs.
        state.open(ModularFace.style)
        state.open(Self.upClose)
        #expect(state.shown == .near)
    }

    @Test func noFacePageForcesADistance() {
        // Widgets show at every distance, so their pages keep the person's pick.
        let declared = FaceCatalog.all.flatMap { definition in
            definition.options.compactMap { option in option.previewDistance.map { "\(definition.id).\(option.id)=\($0)" } }
        }
        #expect(declared.isEmpty)
    }

    @Test func theWidgetsPageKeepsThePickedDistance() {
        var state = EditorDistanceState()
        state.open(FaceOption.widgetGrid)
        #expect(state.shown == .far)
        state.pick(.near)
        state.open(FaceOption.widgetGrid)
        #expect(state.shown == .near)
    }

    @Test func choicesThatOnlyChangeMotionOrTimingShowSymbols() {
        #expect(WeatherFace.style.cardStyle == .symbol)
        #expect(PhotosFace.interval.cardStyle == .symbol)
        #expect(PhotosFace.tint.cardStyle == .faceThumbnail)
        #expect(ModularFace.style.cardStyle == .faceThumbnail)
        #expect(AnalogFace.style.cardStyle == .faceThumbnail)
    }

    // MARK: Personal widgets

    private func widget(_ id: String, personal: Bool) -> WidgetDescriptor {
        WidgetDescriptor(id: id, title: id, systemImage: "square", isPersonal: personal) { _ in EmptyView() }
    }

    @Test func theWallLeavesPersonalWidgetsOutUntilSomeoneIsRecognized() {
        let calendar = widget("calendar", personal: true)
        #expect(FaceWidgetAccess.of(calendar, showPersonal: false, keepsPersonalPlaces: false) == .hidden)
        #expect(FaceWidgetAccess.of(calendar, showPersonal: true, keepsPersonalPlaces: false) == .shown)
        #expect(FaceWidgetAccess.of(widget("lights", personal: false), showPersonal: false, keepsPersonalPlaces: false) == .shown)
    }

    @Test func previewsKeepPersonalWidgetsInPlaceLocked() {
        let calendar = widget("calendar", personal: true)
        #expect(FaceWidgetAccess.of(calendar, showPersonal: false, keepsPersonalPlaces: true) == .locked)
        // Once someone is recognized, nothing is locked.
        #expect(FaceWidgetAccess.of(calendar, showPersonal: true, keepsPersonalPlaces: true) == .shown)
    }

    @Test func aHiddenPersonalWidgetKeepsItsCells() {
        // The wall leaves the cells of a widget it hides empty, so nothing moves when someone is recognized.
        let registry = ModuleRegistry()
        registry.register(widget: widget("calendar", personal: true))
        registry.register(widget: widget("lights", personal: false))
        let layout = FaceWidgetLayout(landscape: [
            FaceWidgetPlacement(widgetID: "calendar", size: .small, cell: FaceGridCell(column: 0, row: 3)),
            FaceWidgetPlacement(widgetID: "lights", size: .small, cell: FaceGridCell(column: 1, row: 3)),
            FaceWidgetPlacement(widgetID: "gone", size: .small, cell: FaceGridCell(column: 2, row: 3)),
        ])
        let face = FaceConfiguration(faceID: "faces.flow", widgetLayout: layout)
        let definition = FlowFace.definition
        let board = FaceWidgetBoard.face(definition, configuration: face, size: CGSize(width: 1210, height: 834),
                                         insets: Theme.Spacing.screenContent, registry: registry)
        #expect(board.items.map(\.widgetID) == ["calendar", "lights"])
        #expect(board.items.map(\.area.column) == [0, 1])
        // A widget whose module is gone stays saved.
        #expect(board.leftOut.map(\.widgetID) == ["gone"])
    }

    @Test func theWidgetsPageHintsAtWhatToDoNext() {
        let grid = FaceGrid(size: CGSize(width: 1210, height: 834), insets: Theme.Spacing.screenContent)
        let empty = FaceWidgetBoard(grid: grid)
        #expect(WidgetsPage.note(for: empty).hasPrefix("Add a widget"))
        let one = empty.adding("a", size: .small)!
        #expect(WidgetsPage.note(for: one).hasPrefix("Drag a widget"))
        var full = empty
        while let next = full.adding("w", size: .small) { full = next }
        #expect(full.items.count == 24)
        #expect(WidgetsPage.note(for: full).hasPrefix("This face is full"))
    }

    // MARK: Layout

    @Test func cardThumbnailsTakeTheScreensShape() {
        let landscape = EditorMetrics.thumbnailSize(screen: CGSize(width: 1210, height: 834))
        #expect(landscape.height <= EditorMetrics.thumbnailHeight + 0.5)
        #expect(abs(landscape.width / landscape.height - 1210 / 834) < 0.01)
        let portrait = EditorMetrics.thumbnailSize(screen: CGSize(width: 834, height: 1210))
        #expect(abs(portrait.width / portrait.height - 834 / 1210) < 0.01)
        #expect(portrait.height <= EditorMetrics.thumbnailHeight + 0.5)
    }

    @Test func slotCardsComeOutInEvenRows() {
        #expect(EditorMetrics.slotColumns(count: 4, width: 1080) == 4)
        #expect(EditorMetrics.slotColumns(count: 4, width: 706) == 2)
        #expect(EditorMetrics.slotColumns(count: 6, width: 1080) == 3)
        #expect(EditorMetrics.slotColumns(count: 4, width: 0) == 1)
        #expect(EditorMetrics.slotRows(count: 4, width: 706) == 2)
    }

    @Test func controlsLeaveMostOfTheScreenToThePreview() {
        let screen = CGSize(width: 1210, height: 834)
        for definition in FaceCatalog.all {
            for option in definition.options {
                let controls = EditorMetrics.controlsHeight(for: option, screen: screen, width: 1080, height: 650)
                #expect(controls <= 650 * EditorMetrics.customShare + 1, "\(definition.id) \(option.id)")
            }
        }
    }
}
