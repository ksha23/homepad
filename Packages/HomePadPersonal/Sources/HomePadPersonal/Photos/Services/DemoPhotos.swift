import Foundation

/// Demo albums for the simulator, which has no iCloud photos. The pictures
/// themselves are drawn by `DemoPhotoArt`.
enum DemoPhotos {
    static let albums: [PhotoAlbum] = [
        PhotoAlbum(id: "demo.library", title: "Library", kind: .library, count: 18, keyPhoto: .demo(4)),
        PhotoAlbum(id: "demo.favorites", title: "Favorites", kind: .favorites, count: 6, keyPhoto: .demo(0)),
        PhotoAlbum(id: "demo.family", title: "Family Shared", kind: .shared, count: 6, keyPhoto: .demo(6)),
        PhotoAlbum(id: "demo.trips", title: "Summer Trips", kind: .user, count: 6, keyPhoto: .demo(12)),
        PhotoAlbum(id: "demo.birthday", title: "Grandma's 80th Birthday at the Lake House", kind: .user, count: 6, keyPhoto: .demo(9)),
    ]

    static var all: [PhotoRef] { (0..<18).map(PhotoRef.demo) }

    static func photos(in albumID: String) -> [PhotoRef] {
        switch albumID {
        case "demo.library": all
        case "demo.favorites": (0..<6).map(PhotoRef.demo)
        case "demo.family": (6..<12).map(PhotoRef.demo)
        case "demo.trips": (12..<18).map(PhotoRef.demo)
        case "demo.birthday": (9..<15).map(PhotoRef.demo)
        default: []
        }
    }
}
