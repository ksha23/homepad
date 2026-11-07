import Foundation
import HomePadCore

/// An album HomePad can show: a PhotoKit collection, the photos someone picked
/// by hand, or a demo album in the simulator.
public struct PhotoAlbum: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The whole photo library (Recents in the system Photos app).
        case library
        case favorites
        /// iCloud Shared Album. Family far away can add to these.
        case shared
        case user
        /// Photos chosen one by one with the system photo picker.
        case picked
        case demo

        /// Shared albums are the household's. Everything else comes from the
        /// iPad's own library, and so do the demo albums standing in for it.
        public var source: PhotoSource {
            switch self {
            case .shared: .sharedAlbums
            case .library, .favorites, .user, .picked, .demo: .library
            }
        }
    }

    public var id: String
    public var title: String
    public var kind: Kind
    /// Photos only. The slideshow, the Photo widget and the faces show photos.
    public var count: Int
    /// Videos, which only the Photos app shows.
    public var videoCount: Int
    /// Cover photo.
    public var keyPhoto: PhotoRef?

    public init(id: String, title: String, kind: Kind, count: Int, videoCount: Int = 0, keyPhoto: PhotoRef? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.count = count
        self.videoCount = videoCount
        self.keyPhoto = keyPhoto
    }

    /// Where the album's photos come from, for `PhotoAccessPolicy`.
    public var source: PhotoSource { kind.source }

    public var systemImage: String {
        switch self.kind {
        case .library: "photo.on.rectangle"
        case .favorites: "heart.fill"
        case .shared: "person.2.crop.square.stack.fill"
        case .user: "rectangle.stack.fill"
        case .picked: "checkmark.circle.fill"
        case .demo: "photo.on.rectangle.angled"
        }
    }

    /// "1 photo", "1,204 photos", "1,204 photos, 38 videos".
    public var countText: String { Self.countText(count, videos: videoCount) }

    public static func countText(_ count: Int, videos: Int = 0) -> String {
        let photos = count == 1 ? "1 photo" : "\(count.formatted()) photos"
        guard videos > 0 else { return photos }
        let videoText = videos == 1 ? "1 video" : "\(videos.formatted()) videos"
        return count == 0 ? videoText : "\(photos), \(videoText)"
    }
}

/// One photo. Library photos are PhotoKit local identifiers. Demo photos are
/// drawn by `DemoPhotoArt` from their index. Phone photos are on the
/// recognized person's own iPhone (`services.phonePhotos`).
public enum PhotoRef: Hashable, Sendable, Identifiable {
    case library(String)
    case demo(Int)
    case phone(PhonePhoto)

    public var id: String {
        switch self {
        case .library(let id): "lib:\(id)"
        case .demo(let index): "demo:\(index)"
        case .phone(let photo): "phone:\(photo.id)"
        }
    }
}

/// Which photos feed the slideshow and the Photo widget.
public struct PhotoSourceSelection: Codable, Hashable, Sendable {
    /// The whole library. Off by default, because the library also holds
    /// screenshots and photos meant for one person.
    public var includeLibrary: Bool
    public var includeFavorites: Bool
    public var includeSharedAlbums: Bool
    /// Extra albums by PhotoKit identifier.
    public var albumIDs: [String]
    /// Photos picked one by one (PhotoKit identifiers from the system picker).
    public var pickedPhotoIDs: [String]

    public init(includeLibrary: Bool = false, includeFavorites: Bool = true, includeSharedAlbums: Bool = true,
                albumIDs: [String] = [], pickedPhotoIDs: [String] = []) {
        self.includeLibrary = includeLibrary
        self.includeFavorites = includeFavorites
        self.includeSharedAlbums = includeSharedAlbums
        self.albumIDs = albumIDs
        self.pickedPhotoIDs = pickedPhotoIDs
    }

    /// Reads selections saved before a field existed, keeping what was saved.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PhotoSourceSelection()
        includeLibrary = try container.decodeIfPresent(Bool.self, forKey: .includeLibrary) ?? defaults.includeLibrary
        includeFavorites = try container.decodeIfPresent(Bool.self, forKey: .includeFavorites) ?? defaults.includeFavorites
        includeSharedAlbums = try container.decodeIfPresent(Bool.self, forKey: .includeSharedAlbums) ?? defaults.includeSharedAlbums
        albumIDs = try container.decodeIfPresent([String].self, forKey: .albumIDs) ?? []
        pickedPhotoIDs = try container.decodeIfPresent([String].self, forKey: .pickedPhotoIDs) ?? []
    }
}
