import Foundation
import HomePadCore

/// Who may see a phone's photo library at this iPad. The Photos access rule
/// (`PhotoAccessPolicy`, the iPad's own library for its owner, shared albums
/// for every recognized member, nothing for guests) answers it: a member's
/// own device is theirs alone (`PhotoSource.memberDevice`).
@MainActor
protocol PhoneLibraryAccess {
    /// True when `viewer`, the member recognized at the iPad (nil for a guest
    /// or someone only picked in People), may see the library of `owner`'s phone.
    func mayShowPhoneLibrary(of owner: UUID, to viewer: UUID?) -> Bool
}

/// A phone's library is its owner's alone: only the owner, recognized, sees it.
struct OwnPhoneOnly: PhoneLibraryAccess {
    func mayShowPhoneLibrary(of owner: UUID, to viewer: UUID?) -> Bool {
        viewer == owner
    }
}

extension PhotoAccessPolicy: PhoneLibraryAccess {
    func mayShowPhoneLibrary(of owner: UUID, to viewer: UUID?) -> Bool {
        PhotoAccessPolicy(ownerID: ownerID, viewerID: viewer).allows(.memberDevice(owner))
    }
}

/// What the Photos app shows of the recognized person's phone.
@MainActor
enum PhoneLibraryVisibility {
    /// The rule when the caller passes none (tests, previews). The Photos app passes the live
    /// `PhotoAccessPolicy`, which gives the same answer for a phone.
    static var access: any PhoneLibraryAccess = OwnPhoneOnly()

    /// The library to show, or nil. It shows only for the member recognized
    /// here, never for someone picked by hand or a guest, only once the phone
    /// answered during this visit, and only when it has something in it.
    static func shown(_ library: PhoneLibrary?, unlockedMember: UUID?, access: (any PhoneLibraryAccess)? = nil) -> PhoneLibrary? {
        let access = access ?? Self.access
        guard let library, let unlockedMember, library.memberID == unlockedMember,
              access.mayShowPhoneLibrary(of: library.memberID, to: unlockedMember),
              library.albums.contains(where: { $0.count > 0 }) else { return nil }
        return library
    }

    /// "From Kyle's iPhone", or "From your iPhone" when the name says nothing.
    static func title(_ library: PhoneLibrary) -> String {
        let name = library.deviceName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "From Your iPhone" : "From \(name)"
    }

    /// The phone's albums as the album grid draws them: Recents and Favorites
    /// on wide covers, then the person's own albums. Empty albums are left out.
    static func section(_ library: PhoneLibrary, onOpen: @escaping (PhoneAlbum) -> Void) -> PhoneAlbumsSection {
        let shown = library.albums.filter { $0.count > 0 }
        let byID = Dictionary(shown.map { ("phone:\($0.id)", $0) }, uniquingKeysWith: { first, _ in first })
        let open: (PhotoAlbum) -> Void = { album in byID[album.id].map(onOpen) }
        let name = library.deviceName.trimmingCharacters(in: .whitespaces)
        return PhoneAlbumsSection(
            title: title(library),
            albumsTitle: name.isEmpty ? "Albums on Your iPhone" : "Albums on \(name)",
            library: shown.filter { $0.kind != .album }.map(photoAlbum),
            albums: shown.filter { $0.kind == .album }.map(photoAlbum),
            onOpen: open
        )
    }

    /// A phone album as the grid's album, its cover drawn from the phone.
    static func photoAlbum(_ album: PhoneAlbum) -> PhotoAlbum {
        let kind: PhotoAlbum.Kind = switch album.kind {
        case .recents: .library
        case .favorites: .favorites
        case .album: .user
        }
        return PhotoAlbum(id: "phone:\(album.id)", title: album.title, kind: kind, count: album.count,
                          keyPhoto: album.keyPhoto.map(PhotoRef.phone))
    }
}

/// The phone's rows in the album grid.
struct PhoneAlbumsSection {
    /// "From Kyle's iPhone", over Recents and Favorites.
    let title: String
    /// "Albums on Kyle's iPhone", over the person's own albums.
    let albumsTitle: String
    let library: [PhotoAlbum]
    let albums: [PhotoAlbum]
    let onOpen: (PhotoAlbum) -> Void
}
