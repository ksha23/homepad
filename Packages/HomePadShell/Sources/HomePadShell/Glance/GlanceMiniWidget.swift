import HomePadCore
import SwiftUI

/// The glance as a mini widget, the first one there is: right of the Home
/// Screen header's lines, and in a face's top left corner when the face's
/// editor puts it there (`MiniGlanceView`).
enum GlanceMiniWidget {
    static let id = "shell.glance.mini"

    /// The header's mini widget until a member changes it: the glance, small.
    static let headerDefault = MiniWidgetPlacement(widgetID: id, size: .small)

    @MainActor
    static func register(in registry: ModuleRegistry) {
        registry.register(miniWidget: MiniWidgetDescriptor(id: id, title: "Glance", systemImage: "square.text.square") { context in
            MiniGlanceView(context: context)
        })
    }
}
