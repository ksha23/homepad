import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// What an app's icon looks like, for the picture the zooming window turns into.
struct ZoomIconFace: Hashable {
    var systemImage: String
    var tint: Color
}

/// Icon pictures, drawn once per icon and look and kept. They match `AppIcon`'s face. Scaling a picture each frame
/// costs nothing, while drawing the icon's symbol at a new size each frame stalled the zoom.
@MainActor
enum ZoomIconPictures {
    /// An icon and how the screen is lit, compared by value. Formatting the tint as text for a key took about
    /// 7 ms of the main thread on an app's first open.
    private struct Key: Hashable {
        var face: ZoomIconFace
        var condition: DisplayCondition
    }

    private static var cache: [Key: UIImage] = [:]

    static func picture(_ face: ZoomIconFace, condition: DisplayCondition) -> UIImage? {
        let key = Key(face: face, condition: condition)
        if let cached = cache[key] { return cached }
        // A full square with no corners of its own: the window's rounded clip gives it the icon's shape, so
        // nothing behind can show through at an edge.
        let size: CGFloat = 160
        let isNight = condition == .night
        let renderer = ImageRenderer(content: Rectangle()
            .fill(isNight ? AnyShapeStyle(Color(white: 0.14)) : AnyShapeStyle(face.tint.gradient))
            .overlay {
                Image(systemName: face.systemImage)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: size, height: size))
        renderer.scale = 3
        let image = renderer.uiImage
        cache[key] = image
        return image
    }
}
