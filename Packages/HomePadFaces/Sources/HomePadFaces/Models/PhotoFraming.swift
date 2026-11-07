import CoreGraphics

/// How a One Photo face frames its photo: how far it is zoomed in, and which
/// point of the photo sits at the middle of the screen. It is saved in the
/// photo's own coordinates, so the framing holds in either orientation, and the
/// photo always covers the whole screen.
struct PhotoFraming: Equatable, Sendable {
    /// 1 fills the screen, as a photo always does. Up to `maxZoom`.
    var zoom: CGFloat = 1
    /// The point of the photo at the screen's center, from 0 to 1 on each axis.
    var center = CGPoint(x: 0.5, y: 0.5)

    static let maxZoom: CGFloat = 4

    /// Configuration keys the framing is saved under.
    static let zoomKey = "photoZoom"
    static let centerXKey = "photoCenterX"
    static let centerYKey = "photoCenterY"

    init(zoom: CGFloat = 1, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.zoom = min(max(zoom, 1), Self.maxZoom)
        self.center = CGPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
    }

    /// The framing saved in a face's values, or the plain fill when none is.
    init(values: [String: String]) {
        func number(_ key: String) -> CGFloat? { values[key].flatMap(Double.init).map { CGFloat($0) } }
        self.init(zoom: number(Self.zoomKey) ?? 1,
                  center: CGPoint(x: number(Self.centerXKey) ?? 0.5, y: number(Self.centerYKey) ?? 0.5))
    }

    /// Saves the framing into a face's values.
    func write(to values: inout [String: String]) {
        values[Self.zoomKey] = String(Double(zoom))
        values[Self.centerXKey] = String(Double(center.x))
        values[Self.centerYKey] = String(Double(center.y))
    }

    /// Removes a saved framing, back to the plain fill.
    static func clear(from values: inout [String: String]) {
        for key in [zoomKey, centerXKey, centerYKey] { values[key] = nil }
    }

    /// Where the photo goes on a screen: its drawn size, and its offset from
    /// centered. The offset never lets an edge of the screen show past the photo.
    func placement(imageSize: CGSize, viewSize: CGSize) -> (size: CGSize, offset: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return (viewSize, .zero) }
        let fill = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height) * zoom
        let size = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let offset = Self.clamped(
            CGSize(width: (0.5 - center.x) * size.width, height: (0.5 - center.y) * size.height),
            size: size, viewSize: viewSize
        )
        return (size, offset)
    }

    /// The framing after the photo was dragged `translation` points from where
    /// it was drawn with this framing.
    func moved(by translation: CGSize, imageSize: CGSize, viewSize: CGSize) -> PhotoFraming {
        let (size, offset) = placement(imageSize: imageSize, viewSize: viewSize)
        guard size.width > 0, size.height > 0 else { return self }
        let moved = Self.clamped(CGSize(width: offset.width + translation.width, height: offset.height + translation.height),
                                 size: size, viewSize: viewSize)
        return PhotoFraming(zoom: zoom, center: CGPoint(x: 0.5 - moved.width / size.width, y: 0.5 - moved.height / size.height))
    }

    /// The framing zoomed by `factor` around the screen's center.
    func zoomed(by factor: CGFloat) -> PhotoFraming {
        PhotoFraming(zoom: zoom * factor, center: center)
    }

    /// Maps a rectangle on the screen (0 to 1 of the view) to the part of the
    /// photo under it (0 to 1 of the image), for the depth effect's checks.
    func imageRect(forViewRect rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let (size, offset) = placement(imageSize: imageSize, viewSize: viewSize)
        guard size.width > 0, size.height > 0 else { return rect }
        let left = (viewSize.width - size.width) / 2 + offset.width
        let top = (viewSize.height - size.height) / 2 + offset.height
        return CGRect(
            x: (rect.minX * viewSize.width - left) / size.width,
            y: (rect.minY * viewSize.height - top) / size.height,
            width: rect.width * viewSize.width / size.width,
            height: rect.height * viewSize.height / size.height
        )
    }

    private static func clamped(_ offset: CGSize, size: CGSize, viewSize: CGSize) -> CGSize {
        let maxX = max(0, (size.width - viewSize.width) / 2)
        let maxY = max(0, (size.height - viewSize.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}
