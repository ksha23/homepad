import CoreGraphics
import Foundation

/// A photo the Photos face can show: a PhotoKit asset or a generated demo scene.
struct PhotoRef: Hashable, Sendable, Identifiable {
    enum Source: Hashable, Sendable {
        case library(localIdentifier: String)
        case demo(index: Int)
    }

    let source: Source
    let date: Date?

    var id: String {
        switch source {
        case .library(let identifier): "library:\(identifier)"
        case .demo(let index): "demo:\(index)"
        }
    }
}

/// A photo ready to draw: the picture, an optional subject mask for the depth
/// effect, and colors derived from it.
struct PhotoFrame: Identifiable, @unchecked Sendable {
    let ref: PhotoRef
    let image: CGImage
    /// White where the subject is, transparent elsewhere. Same aspect as `image`.
    let mask: CGImage?
    let sample: MaskSample?
    let tint: PhotoTint

    var id: String { ref.id }
    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
}

/// Which photos the face shows. Stored in the saved face's values.
enum PhotoSourceKind: String, CaseIterable, Identifiable, Sendable {
    case featured, library, favorites, portraits, album, picked, single

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .library: "Library"
        case .favorites: "Favorites"
        case .portraits: "Portraits"
        case .album: "Album"
        case .picked: "Chosen Photos"
        case .single: "One Photo"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: "sparkles"
        case .library: "photo.on.rectangle"
        case .favorites: "heart.fill"
        case .portraits: "person.crop.rectangle.fill"
        case .album: "rectangle.stack.fill"
        case .picked: "photo.on.rectangle.angled"
        case .single: "photo"
        }
    }
}

/// Everything needed to fetch the photos for one saved face.
struct PhotoQuery: Hashable, Sendable {
    var source: PhotoSourceKind
    var albumID: String?
    var pickedIDs: [String]
    /// The photo a `.single` face shows.
    var singleID: String?

    /// True when the face shows one photo that never changes or moves.
    var isStill: Bool { source == .single }
}

/// A photo album the user can choose, including iCloud Shared Albums.
struct PhotoAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
    let isShared: Bool
}
