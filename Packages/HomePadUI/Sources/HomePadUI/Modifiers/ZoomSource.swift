import SwiftUI

/// Something on the Home Screen or a face that opens an app, as the app zoom
/// sees it: where it is and its shape. An app grows out of what was touched to
/// open it and shrinks back into it when it closes.
///
/// Anything that opens an app reports itself with `zoomSource(_:shape:)`. The
/// shell picks the one under the finger when an app opens, so how the app was
/// asked to open (a button, an event a module posts, a redirect) does not
/// matter, and nothing has to tell the shell where it came from.
public struct ZoomSource: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// An app icon. The window turns into the icon's picture, and the icon
        /// hides while its app is in flight, since the window is it.
        case icon
        /// Something drawn in place, such as a widget. The window takes its
        /// shape and corners and melts into it, so it stays in view.
        case surface(cornerRadius: CGFloat)
        /// A capsule, such as a pill at the top of the screen, melted into like a surface.
        case capsule
    }

    /// Where it is, in window coordinates: what the window grows out of and lands on.
    public var frame: CGRect
    public var shape: Shape
    /// Where a touch counts as being on it, which can take in more than `frame`: a widget's or an icon's
    /// name under it opens the same app, and the app should still come out of the widget or the icon.
    public var hitFrame: CGRect

    public init(frame: CGRect, shape: Shape, hitFrame: CGRect? = nil) {
        self.frame = frame
        self.shape = shape
        self.hitFrame = hitFrame ?? frame
    }

    /// The corners the window lands with. Nil for an icon, whose corners follow its size.
    public var cornerRadius: CGFloat? {
        switch shape {
        case .icon: nil
        case .surface(let radius): radius
        case .capsule: min(frame.width, frame.height) / 2
        }
    }
}

/// Every zoom source drawn now, by id. The id stays the same while the source
/// is on screen (an icon's app, a widget's placement, a pill's role), so the
/// app finds it again when it closes, wherever it has moved.
public struct ZoomSourcesKey: PreferenceKey {
    public static let defaultValue: [String: ZoomSource] = [:]

    public static func reduce(value: inout [String: ZoomSource], nextValue: () -> [String: ZoomSource]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension EnvironmentValues {
    /// The space zoom sources measure themselves in. The window, unless a host
    /// of its own names another that starts at the window's corner, as the Home
    /// Screen does, since it scales down while an app is open over it.
    @Entry var zoomSourceSpace: CoordinateSpace = .global
}

public extension View {
    /// Reports this view as something an app opens from, under `id`.
    /// - Parameter isEnabled: False for a copy that is not where the source lives, such as one lifted under a finger.
    func zoomSource(_ id: String, shape: ZoomSource.Shape, isEnabled: Bool = true) -> some View {
        modifier(ZoomSourceReporter(id: id, isEnabled: isEnabled) { ZoomSource(frame: $0, shape: shape) })
    }

    /// Reports this view's part that `source` picks out of its frame, under `id`. An app icon's tile
    /// reports only its icon, not its label.
    func zoomSource(_ id: String, isEnabled: Bool = true, source: @escaping @Sendable (CGRect) -> ZoomSource) -> some View {
        modifier(ZoomSourceReporter(id: id, isEnabled: isEnabled, source: source))
    }
}

/// Follows the view's frame with `onGeometryChange`, so a source in a scroll view moves with it.
private struct ZoomSourceReporter: ViewModifier {
    let id: String
    let isEnabled: Bool
    let source: @Sendable (CGRect) -> ZoomSource
    @Environment(\.zoomSourceSpace) private var space
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: space) } action: { frame = $0 }
            .preference(key: ZoomSourcesKey.self, value: isEnabled ? frame.map { [id: source($0)] } ?? [:] : [:])
    }
}
