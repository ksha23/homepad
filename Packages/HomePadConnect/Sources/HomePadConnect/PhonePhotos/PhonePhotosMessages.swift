import Foundation
import HomePadCore

// Each person's own phone photos (`RemoteProtocol.phonePhotos` and later),
// one kind of data a phone visit carries (`PhoneVisitMessages.swift` has the
// visit's hello, challenge and close). Inside an open visit:
//
//   phone   photos.offer      shares or stops sharing, with its wake tag
//   HomePad photos.request    albums, an album's photos, or images
//   phone   photos.reply      albums or photos, and photos.image per image
extension PeerMessageType {
    /// A phone shares its photos with a HomePad, or stops (`PhotoShareOffer`).
    public static let photosOffer = PeerMessageType("photos.offer")
    /// The HomePad asks for albums, photos or images (`PhotosRequest`).
    public static let photosRequest = PeerMessageType("photos.request")
    /// The phone's answer with albums or photos (`PhotosReply`).
    public static let photosReply = PeerMessageType("photos.reply")
    /// One JPEG in the attachment (`PhotosImage`).
    public static let photosImage = PeerMessageType("photos.image")
}

/// Limits of phone photos.
enum PhonePhotosPolicy {
    /// Longest side of a grid thumbnail, in pixels.
    static let thumbnailPixels = 360
    /// Longest side of a full-screen image, in pixels. A 13-inch iPad is 2752 wide.
    static let screenPixels = 2048
    /// Most photos listed for one album.
    static let listLimit = 500
    /// Most images in one request, so one answer never holds the session long.
    static let imagesPerRequest = 24
}

/// Body of `photos.offer`: whether this phone shares its photos with the
/// HomePad, and the tag it writes over Bluetooth so the HomePad knows whom
/// to wake. The tag is random, made for this HomePad, and means nothing else.
public struct PhotoShareOffer: Codable, Equatable, Sendable {
    public var isSharing: Bool
    public var wakeTag: Data?

    public init(isSharing: Bool, wakeTag: Data?) {
        self.isSharing = isSharing
        self.wakeTag = wakeTag
    }
}

/// How big an image the HomePad wants.
public enum PhotoImageSize: String, Codable, Sendable {
    case thumbnail, screen

    var pixels: Int {
        switch self {
        case .thumbnail: PhonePhotosPolicy.thumbnailPixels
        case .screen: PhonePhotosPolicy.screenPixels
        }
    }
}

/// Body of `photos.request`. Exactly one of the three asks is set.
public struct PhotosRequest: Codable, Equatable, Sendable {
    public var id: UUID
    /// The album list.
    public var albums: Bool?
    /// The photos of one album, newest first.
    public var albumID: String?
    /// These images, each answered with its own `photos.image`.
    public var imageIDs: [String]?
    public var size: PhotoImageSize?

    public static func albumList() -> PhotosRequest { PhotosRequest(id: UUID(), albums: true) }
    public static func photos(in albumID: String) -> PhotosRequest { PhotosRequest(id: UUID(), albumID: albumID) }
    public static func images(_ ids: [String], size: PhotoImageSize) -> PhotosRequest {
        PhotosRequest(id: UUID(), imageIDs: Array(ids.prefix(PhonePhotosPolicy.imagesPerRequest)), size: size)
    }
}

/// Body of `photos.reply`.
public struct PhotosReply: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var albums: [PhoneAlbum]?
    public var photos: [PhonePhoto]?
    /// The album was not found, or the library could not be read.
    public var failed: Bool?

    public init(requestID: UUID, albums: [PhoneAlbum]? = nil, photos: [PhonePhoto]? = nil, failed: Bool? = nil) {
        self.requestID = requestID
        self.albums = albums
        self.photos = photos
        self.failed = failed
    }
}

/// Body of `photos.image`. The JPEG is the message's attachment, missing
/// when the phone could not make it.
public struct PhotosImage: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var photoID: String
    public var size: PhotoImageSize

    public init(requestID: UUID, photoID: String, size: PhotoImageSize) {
        self.requestID = requestID
        self.photoID = photoID
        self.size = size
    }
}
