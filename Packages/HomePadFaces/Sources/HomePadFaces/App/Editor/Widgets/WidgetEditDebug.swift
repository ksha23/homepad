import CoreGraphics
import Foundation
import HomePadCore

/// What the widget gallery opens on: its list, or one widget's sizes.
struct WidgetGalleryRequest: Identifiable {
    let id = UUID()
    var widgetID: String?
    var size: WidgetSize?
}

/// Debug only: launch arguments that hold the widgets page in a state for a
/// screenshot, since a simulator screenshot cannot drag. With
/// `-HomePadOpenApp faces -HomePadFacesEdit <faceID> -HomePadFacesEditWidgets YES`:
///
///     -HomePadFacesWidgetOrientation portrait   arrange the other orientation
///     -HomePadFacesWidgetSelect 0               select the first widget (its resize handle shows)
///     -HomePadFacesWidgetDrag 0@300,-200        hold the first widget lifted, moved this far (face points)
///     -HomePadFacesWidgetResize 0@200,0         hold the first widget's handle dragged this far
///     -HomePadFacesWidgetGallery YES            open the widget gallery
///     -HomePadFacesWidgetGalleryItem kitchen.timers   open it on that widget's sizes
///     -HomePadFacesWidgetGallerySize large      at that size
///
/// Widgets count in the face's saved order. `-HomePadFacesWidgets` puts widgets on the face first.
struct WidgetEditDebug {
    var orientation: FaceGrid.Orientation?
    var select: Int?
    var drag: (index: Int, translation: CGSize)?
    var resize: (index: Int, translation: CGSize)?
    var gallery: WidgetGalleryRequest?

    /// The state the launch arguments ask for, or nil when they ask for none.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> WidgetEditDebug? {
        #if DEBUG
        var debug = WidgetEditDebug()
        debug.orientation = defaults.string(forKey: "HomePadFacesWidgetOrientation").flatMap(FaceGrid.Orientation.init(rawValue:))
        debug.select = defaults.string(forKey: "HomePadFacesWidgetSelect").flatMap { Int($0) }
        debug.drag = defaults.string(forKey: "HomePadFacesWidgetDrag").flatMap(Self.indexAndOffset)
        debug.resize = defaults.string(forKey: "HomePadFacesWidgetResize").flatMap(Self.indexAndOffset)
        let item = defaults.string(forKey: "HomePadFacesWidgetGalleryItem")
        if defaults.bool(forKey: "HomePadFacesWidgetGallery") || item != nil {
            debug.gallery = WidgetGalleryRequest(
                widgetID: item, size: defaults.string(forKey: "HomePadFacesWidgetGallerySize").flatMap(WidgetSize.init(rawValue:)))
        }
        let asksForAnything = debug.orientation != nil || debug.select != nil || debug.drag != nil
            || debug.resize != nil || debug.gallery != nil
        return asksForAnything ? debug : nil
        #else
        return nil
        #endif
    }

    /// Puts the session in the state asked for, on the face's saved board.
    /// - Parameter sizes: The sizes a widget supports.
    @MainActor
    func apply(to session: WidgetEditSession, board: FaceWidgetBoard, sizes: (String) -> [WidgetSize]) {
        if let select, board.items.indices.contains(select) {
            session.selection = board.items[select].id
        }
        if let drag, board.items.indices.contains(drag.index) {
            session.beginDrag(board.items[drag.index].id, on: board)
            session.drag(by: drag.translation)
        }
        if let resize, board.items.indices.contains(resize.index) {
            let item = board.items[resize.index]
            session.beginResize(item.id, on: board)
            session.resize(by: resize.translation, sizes: sizes(item.widgetID))
        }
    }

    /// "0@300,-200": a widget's index and an offset.
    static func indexAndOffset(_ text: String) -> (index: Int, translation: CGSize)? {
        let parts = text.split(separator: "@")
        guard parts.count == 2, let index = Int(parts[0]) else { return nil }
        let numbers = parts[1].split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        return (index, CGSize(width: numbers[0], height: numbers[1]))
    }
}
