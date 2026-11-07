import Foundation

/// Where a photo comes from, for `PhotoAccessPolicy`.
public enum PhotoSource: Hashable, Sendable {
    /// Anything from the iPad's own photo library: the whole library, Favorites,
    /// the albums in it, videos, recents, the system photo picker and the sheet
    /// that chooses which photos HomePad may see. It belongs to the Apple
    /// Account the iPad is signed in to, so it is one person's.
    case library
    /// iCloud Shared Albums the iPad's account joined. Family far away add to
    /// them, so they are the household's.
    case sharedAlbums
    /// Photos a member's own iPhone shares through the companion, for that member.
    case memberDevice(UUID)
}

/// Who may see which photos.
///
/// - The library owner, the member whose Apple Account the iPad's library
///   belongs to, sees everything from the library while they are recognized.
/// - Every recognized member sees iCloud Shared Albums, and their own iPhone's photos.
/// - Guests, and members only picked in the People menu, see nothing.
///
/// Photos faces and the Photo widget are picture frames: they show the sources
/// picked for them to whoever is in the room, and do not ask this policy.
public struct PhotoAccessPolicy: Equatable, Sendable {
    /// The library owner, nil while the household has nobody in it.
    public var ownerID: UUID?
    /// The member recognized at the screen (`Household.unlockedMember`), nil for a guest.
    public var viewerID: UUID?

    public init(ownerID: UUID?, viewerID: UUID?) {
        self.ownerID = ownerID
        self.viewerID = viewerID
    }

    /// True when the person at the screen may see photos from `source`.
    public func allows(_ source: PhotoSource) -> Bool {
        guard let viewerID else { return false }
        switch source {
        case .library: return viewerID == ownerID
        case .sharedAlbums: return true
        case .memberDevice(let memberID): return memberID == viewerID
        }
    }

    /// True when the person at the screen may see any photos at all. Only a
    /// recognized member may, so a guest gets the recognition gate.
    public var allowsAnyPhotos: Bool { viewerID != nil }

    /// True when the library is shown to its owner, so the system photo
    /// picker and "Allow More Photos" may be offered.
    public var allowsLibrary: Bool { allows(.library) }

    /// The sources at least one member of the household may see, which is
    /// all that background work may read ahead of time: the library and
    /// shared albums while there is an owner, nothing for an empty household.
    public static func householdSources(ownerID: UUID?) -> Set<PhotoSource> {
        ownerID == nil ? [] : [.library, .sharedAlbums]
    }
}

/// The member whose Apple Account the iPad's photo library belongs to.
public enum PhotoLibraryOwner {
    /// The owner picked in Settings, Personal Info. Not synced: each iPad's
    /// library belongs to the account that iPad is signed in to.
    public static let setting = SettingKey<UUID?>("core.photos.libraryOwner", default: nil)

    /// The member picked in Settings while they are still in the household,
    /// else the first admin (who usually set the iPad up with their account),
    /// else the first member. Nil for an empty household.
    public static func resolve(chosen: UUID?, members: [HouseholdMember]) -> UUID? {
        if let chosen, members.contains(where: { $0.id == chosen }) { return chosen }
        return (members.first { $0.isAdmin } ?? members.first)?.id
    }
}

public extension AppServices {
    /// The library owner right now, after `PhotoLibraryOwner.resolve`.
    var photoLibraryOwnerID: UUID? {
        PhotoLibraryOwner.resolve(chosen: settings[PhotoLibraryOwner.setting], members: household.members)
    }

    /// Which photos the person at the screen may see right now. Reading it in
    /// a view body redraws the view when someone is recognized or leaves, or
    /// the owner changes.
    var photoAccess: PhotoAccessPolicy {
        PhotoAccessPolicy(ownerID: photoLibraryOwnerID, viewerID: household.unlockedMember?.id)
    }
}
