import Foundation

/// The recognized person's own iPhone photo library, read on their phone and
/// sent to this HomePad over the local peer link. The Connect module installs
/// the real service and the Personal module's Photos app shows it.
///
/// `library` is nil unless a member is recognized here (not just picked in
/// People), their own iPhone is linked to them and shares its photos, and that
/// phone has answered during this visit. It goes back to nil the moment the
/// person stops being recognized.
@MainActor
public protocol PhonePhotosService: AnyObject {
    /// The library of the person at the HomePad, or nil.
    var library: PhoneLibrary? { get }

    /// The photos of one of the library's albums, newest first. Empty when
    /// the phone cannot be reached and nothing is saved.
    func photos(in album: PhoneAlbum) async -> [PhonePhoto]

    /// A small JPEG for grids and album covers, from the iPad's saved copy or the phone.
    func thumbnail(of photo: PhonePhoto.ID) async -> Data?

    /// A screen-sized JPEG, from the iPad's saved copy or the phone. Nil when
    /// neither has it, and the photo then stays at its thumbnail.
    func fullImage(of photo: PhonePhoto.ID) async -> Data?
}

/// A person's phone library as one HomePad sees it during a visit.
public struct PhoneLibrary: Equatable, Sendable {
    /// Whose phone it is. Always the member recognized at the HomePad.
    public var memberID: UUID
    /// The phone's name, such as "Kyle's iPhone".
    public var deviceName: String
    /// Recents, Favorites and the person's own albums, in that order.
    public var albums: [PhoneAlbum]
    /// True while the phone answers right now. When false, what was saved
    /// on the iPad during this visit still shows.
    public var isConnected: Bool

    public init(memberID: UUID, deviceName: String, albums: [PhoneAlbum], isConnected: Bool) {
        self.memberID = memberID
        self.deviceName = deviceName
        self.albums = albums
        self.isConnected = isConnected
    }
}

/// An album on a person's phone.
public struct PhoneAlbum: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Every photo, newest first (Recents in the Photos app).
        case recents
        case favorites
        /// An album the person made.
        case album
    }

    /// The phone's own identifier for the album.
    public var id: String
    public var title: String
    public var kind: Kind
    /// Photos only. Videos stay on the phone.
    public var count: Int
    public var keyPhoto: PhonePhoto?

    public init(id: String, title: String, kind: Kind, count: Int, keyPhoto: PhonePhoto? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.count = count
        self.keyPhoto = keyPhoto
    }

    public var systemImage: String {
        switch kind {
        case .recents: "photo.on.rectangle"
        case .favorites: "heart.fill"
        case .album: "rectangle.stack.fill"
        }
    }
}

/// One photo on a person's phone.
public struct PhonePhoto: Identifiable, Hashable, Codable, Sendable {
    /// The phone's own identifier for the photo.
    public var id: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var date: Date?

    public init(id: String, pixelWidth: Int, pixelHeight: Int, date: Date? = nil) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.date = date
    }

    /// Width over height, 4:3 when the phone did not say.
    public var aspectRatio: Double {
        guard pixelWidth > 0, pixelHeight > 0 else { return 4.0 / 3.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

/// Used until a module installs a real service: nobody's phone library shows.
@MainActor
public final class NoPhonePhotos: PhonePhotosService {
    public init() {}

    public var library: PhoneLibrary? { nil }
    public func photos(in album: PhoneAlbum) async -> [PhonePhoto] { [] }
    public func thumbnail(of photo: PhonePhoto.ID) async -> Data? { nil }
    public func fullImage(of photo: PhonePhoto.ID) async -> Data? { nil }
}
