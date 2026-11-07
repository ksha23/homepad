import Foundation

// The parts of a mini widget besides its descriptor (`MiniWidgetDescriptor`,
// beside `WidgetDescriptor` in Registry.swift).

/// How much a mini widget says. Every size is one row as tall as the profile
/// button, so a size changes the words and detail it shows, never its height.
public enum MiniWidgetSize: String, Codable, CaseIterable, Sendable {
    /// A symbol and a count for each thing.
    case small
    /// Short words too: "3 events", "5 lights on".
    case medium
    /// A second line with the detail: the next event, the rooms that are lit.
    case large

    /// The size's name in the editors and in VoiceOver.
    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// A mini widget where it is placed: which one and how large. The Home
/// Screen's header holds one for each member, and each saved face can hold
/// one in its top left corner.
public struct MiniWidgetPlacement: Codable, Hashable, Sendable {
    /// The `MiniWidgetDescriptor.id` it shows.
    public var widgetID: String
    public var size: MiniWidgetSize

    public init(widgetID: String, size: MiniWidgetSize) {
        self.widgetID = widgetID
        self.size = size
    }
}

/// What a mini widget sits on, which sets the color of its text.
public enum MiniWidgetSurface: Sendable {
    /// Straight on the Home Screen's wallpaper, beside the header's lines:
    /// white with the wallpaper labels' shadow, like the lines.
    case wallpaper
    /// On a glass capsule of its own, as on a face: the glass's primary
    /// color, which follows the glass over a bright or a dark backdrop.
    case glass
}

/// Everything the place that draws a mini widget tells it. The widget fits
/// itself to the width it is offered, stepping down to less before anything
/// is cut off, as the glance does.
public struct MiniWidgetContext {
    public var size: MiniWidgetSize
    public var surface: MiniWidgetSurface
    /// The point size of its text. The header passes its lines' size, so the
    /// widget reads as part of them, and a face one that fits the capsule.
    public var textSize: CGFloat
    /// Room to leave before it, left out while it shows nothing.
    public var leadingGap: CGFloat
    /// True where it must show something however little room it has: in
    /// edit mode, so it can be resized or removed, and on its own glass,
    /// which would otherwise be empty.
    public var keepsSomething: Bool
    /// Opens an app for a tap on one of its parts. Nil where taps do not
    /// open apps: in edit mode, in previews and on a face that is not on the wall.
    public var openApp: (@MainActor (String) -> Void)?

    public init(size: MiniWidgetSize, surface: MiniWidgetSurface, textSize: CGFloat, leadingGap: CGFloat = 0,
                keepsSomething: Bool = false, openApp: (@MainActor (String) -> Void)? = nil) {
        self.size = size
        self.surface = surface
        self.textSize = textSize
        self.leadingGap = leadingGap
        self.keepsSomething = keepsSomething
        self.openApp = openApp
    }
}
