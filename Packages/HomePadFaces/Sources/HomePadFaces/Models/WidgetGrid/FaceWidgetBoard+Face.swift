import CoreGraphics
import HomePadCore
import SwiftUI

extension FaceWidgetBoard {
    /// The board a saved face draws at a size: its widgets for that size's
    /// orientation, on its grid, skipping widgets whose module is gone. A
    /// stack takes the sizes all its installed widgets come in.
    @MainActor
    static func face(_ definition: FaceDefinition, configuration: FaceConfiguration, size: CGSize,
                     insets: EdgeInsets, registry: ModuleRegistry) -> FaceWidgetBoard {
        let support = definition.widgets
        let grid = support.grid(configuration: configuration, size: size, insets: insets)
        let layout = configuration.widgets(legacySize: support.legacySize)
        return FaceWidgetBoard(placements: layout.placements(for: grid.orientation), grid: grid,
                               fill: support.fill(for: grid.orientation),
                               sizes: { registry.widget($0)?.supportedSizes ?? [] },
                               stackSizes: { id in
                                   layout.stack(for: id).map { stackSizes($0, registry: registry) }
                               },
                               anchors: { registry.widget($0)?.anchor ?? .faceFill })
    }

    /// The sizes a stack can take: those all its installed widgets come in.
    /// Empty when none of them is installed, so the stack waits like a widget whose module is gone.
    @MainActor
    static func stackSizes(_ stack: WidgetStack, registry: ModuleRegistry) -> [WidgetSize] {
        let installed = stack.members.compactMap { registry.widget($0.widgetID)?.supportedSizes }
        return installed.isEmpty ? [] : WidgetStack.sizes(supportedByAll: installed)
    }
}
