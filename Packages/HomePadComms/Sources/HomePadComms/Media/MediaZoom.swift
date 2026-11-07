import SwiftUI

private struct MediaZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace a photo block shares with its viewer, so the viewer zooms out of the tapped
    /// photo and back into the one on screen when it closes.
    var mediaZoom: Namespace.ID? {
        get { self[MediaZoomKey.self] }
        set { self[MediaZoomKey.self] = newValue }
    }
}

extension View {
    /// Marks this photo as the place the viewer zooms from and back to.
    func mediaZoomSource(id: String, cornerRadius: CGFloat) -> some View {
        modifier(MediaZoomSource(id: id, cornerRadius: cornerRadius))
    }
}

private struct MediaZoomSource: ViewModifier {
    @Environment(\.mediaZoom) private var zoom
    let id: String
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let zoom {
            content.matchedTransitionSource(id: id, in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)) }
        } else {
            content
        }
    }
}
