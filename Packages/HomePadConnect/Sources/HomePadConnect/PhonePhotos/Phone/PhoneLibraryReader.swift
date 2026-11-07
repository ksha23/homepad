import Foundation
import HomePadCore
import Photos
import UIKit

/// On a phone: reads its own photo library for a HomePad. PhotoKit on a
/// device, made-up photos in the simulator for screenshots.
@MainActor
protocol PhoneLibraryReader: AnyObject {
    /// True when the person allowed HomePad all photos or some.
    var hasAccess: Bool { get }
    /// Asks for access. Call only after the person tapped something that explains why.
    func requestAccess() async -> Bool
    /// Recents, Favorites and the person's own albums.
    func albums() async -> [PhoneAlbum]
    /// The photos of one album, newest first, nil when the album is gone.
    func photos(in albumID: String, limit: Int) async -> [PhonePhoto]?
    /// A JPEG whose longest side is at most `pixels`.
    func jpeg(for photoID: String, pixels: Int) async -> Data?
}

/// PhotoKit. Photos only, no videos. With limited access only the photos the
/// person allowed are there, as in any app.
@MainActor
final class PhotoKitLibraryReader: PhoneLibraryReader {
    private let imageManager = PHImageManager.default()
    /// Most of the person's own albums listed.
    private let albumLimit = 40

    var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    func requestAccess() async -> Bool {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return hasAccess
    }

    func albums() async -> [PhoneAlbum] {
        guard hasAccess else { return [] }
        let limit = albumLimit
        return await Task.detached(priority: .userInitiated) { PhotoKitAlbums.read(albumLimit: limit) }.value
    }

    func photos(in albumID: String, limit: Int) async -> [PhonePhoto]? {
        guard hasAccess else { return nil }
        return await Task.detached(priority: .userInitiated) { PhotoKitAlbums.photos(in: albumID, limit: limit) }.value
    }

    func jpeg(for photoID: String, pixels: Int) async -> Data? {
        guard hasAccess, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photoID], options: nil).firstObject,
              asset.mediaType == .image else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        // A full-size photo kept only in iCloud downloads, which can take a
        // while. Thumbnails are always on the phone.
        options.isNetworkAccessAllowed = pixels > PhonePhotosPolicy.thumbnailPixels
        let size = CGSize(width: pixels, height: pixels)
        let image: UIImage? = await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return nil }
        return await Task.detached(priority: .userInitiated) { image.jpegData(compressionQuality: 0.8) }.value
    }
}

/// PhotoKit fetches, off the main thread.
private enum PhotoKitAlbums {
    static let recentsID = "phone.recents"
    static let favoritesID = "phone.favorites"

    static func read(albumLimit: Int) -> [PhoneAlbum] {
        var albums: [PhoneAlbum] = []
        let everything = PHAsset.fetchAssets(with: imageOptions())
        albums.append(PhoneAlbum(id: recentsID, title: "Recents", kind: .recents, count: everything.count,
                                 keyPhoto: everything.firstObject.map(photo)))
        let favorites = PHAsset.fetchAssets(with: imageOptions(favoritesOnly: true))
        albums.append(PhoneAlbum(id: favoritesID, title: "Favorites", kind: .favorites, count: favorites.count,
                                 keyPhoto: favorites.firstObject.map(photo)))
        let own = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        own.enumerateObjects { collection, _, stop in
            let assets = PHAsset.fetchAssets(in: collection, options: imageOptions())
            if assets.count > 0 {
                albums.append(PhoneAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album",
                                         kind: .album, count: assets.count, keyPhoto: assets.firstObject.map(photo)))
            }
            if albums.count >= albumLimit + 2 { stop.pointee = true }
        }
        return albums
    }

    static func photos(in albumID: String, limit: Int) -> [PhonePhoto]? {
        let options = imageOptions(favoritesOnly: albumID == favoritesID)
        options.fetchLimit = limit
        let assets: PHFetchResult<PHAsset>
        if albumID == recentsID || albumID == favoritesID {
            assets = PHAsset.fetchAssets(with: options)
        } else {
            guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else {
                return nil
            }
            assets = PHAsset.fetchAssets(in: collection, options: options)
        }
        return (0..<assets.count).map { photo(assets.object(at: $0)) }
    }

    private static func imageOptions(favoritesOnly: Bool = false) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let image = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.predicate = favoritesOnly
            ? NSCompoundPredicate(andPredicateWithSubpredicates: [image, NSPredicate(format: "favorite == YES")])
            : image
        return options
    }

    private static func photo(_ asset: PHAsset) -> PhonePhoto {
        PhonePhoto(id: asset.localIdentifier, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight, date: asset.creationDate)
    }
}
