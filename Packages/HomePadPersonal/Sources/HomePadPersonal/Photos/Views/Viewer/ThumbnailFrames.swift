import CoreGraphics

/// Where the grid's thumbnails sit on screen, in global coordinates, so the
/// viewer can grow out of one and shrink back into it. A plain class rather
/// than state: thumbnails move on every frame of a scroll, and nothing needs
/// to redraw when they do.
@MainActor
final class ThumbnailFrames {
    private var frames: [PhotoRef: CGRect] = [:]

    func set(_ frame: CGRect, for photo: PhotoRef) {
        frames[photo] = frame
    }

    func remove(_ photo: PhotoRef) {
        frames[photo] = nil
    }

    func frame(of photo: PhotoRef) -> CGRect? {
        frames[photo]
    }
}
