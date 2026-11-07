import SwiftUI

/// Everything HomePad knows about one face kind: how to draw it and which
/// curated options its editor offers. `FaceCatalog` lists them all.
struct FaceDefinition: Identifiable {
    let id: String
    let title: String
    /// One line for the gallery, for example "Big time behind the people in your photos".
    let summary: String
    let systemImage: String
    let sortOrder: Int
    /// Editor pages, in order. Empty for faces with nothing to customize.
    let options: [FaceOption]
    /// How the face takes widgets: where its own content is, and where new widgets go.
    let widgets: FaceWidgetSupport
    let makeView: @MainActor () -> AnyView

    /// - Parameter widgets: How the face takes widgets. Anywhere by default, for art faces.
    init<V: View>(
        id: String, title: String, summary: String, systemImage: String, sortOrder: Int,
        options: [FaceOption] = [], widgets: FaceWidgetSupport = .anywhere, @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.sortOrder = sortOrder
        self.options = options
        self.widgets = widgets
        self.makeView = { AnyView(view()) }
    }

    /// The option with an ID, if this face has it.
    func option(_ id: String) -> FaceOption? {
        options.first { $0.id == id }
    }

    /// The options that apply to a configuration, in order: the editor's
    /// pages. A face that takes widgets ends with the widgets page.
    @MainActor
    func options(for configuration: FaceConfiguration) -> [FaceOption] {
        let own = options.filter { $0.isShown(configuration) }
        return widgets.allowsWidgets ? own + [.widgetGrid] : own
    }

    /// A short description of a configuration, such as "Heavy, Clover" or
    /// "Digital, Ocean, Navy Text, Pink Accent".
    @MainActor
    func caption(for configuration: FaceConfiguration) -> String {
        options(for: configuration).compactMap { option -> String? in
            let value = configuration.value(option)
            switch option.kind {
            case .choices(let choices): return choices.first { $0.id == value }?.title
            case .colors: return configuration.colors(option).caption
            case .slots, .custom, .widgetGrid: return nil
            }
        }
        .joined(separator: ", ")
    }
}
