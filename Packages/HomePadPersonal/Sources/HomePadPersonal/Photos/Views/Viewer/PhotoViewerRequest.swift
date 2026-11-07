import Foundation

/// What the full-screen viewer shows: the photos and videos of a grid, in grid
/// order, and where to start.
struct PhotoViewerRequest: Identifiable {
    enum Mode {
        /// Opened on a photo the person tapped. It stays until they page or close.
        case browse
        /// Play Slideshow: moves on by itself, with crossfades and a slow zoom.
        case slideshow
    }

    let id = UUID()
    let photos: [PhotoRef]
    let startIndex: Int
    /// The album's name, for the header.
    let title: String
    let mode: Mode

    init(photos: [PhotoRef], start: PhotoRef?, title: String, mode: Mode) {
        self.photos = photos
        self.startIndex = start.flatMap { photos.firstIndex(of: $0) } ?? 0
        self.title = title
        self.mode = mode
    }
}
