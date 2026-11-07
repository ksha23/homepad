import Foundation
import HomePadCore
import ImageIO
import Photos

/// Reads photos from the system Photos library with PhotoKit. Fetches run
/// off the main thread. Access is requested only when a person asks for it.
enum PhotoLibrarySource {
    private static let log = Log.make("Faces.Photos")

    // MARK: Access

    enum Access: Equatable {
        case notAsked, allowed, limited, denied
    }

    static var access: Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .allowed
        case .limited: .limited
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Shows the system prompt. Returns true when photos can be read.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: Fetching

    /// The photos for a query, newest first, at most `limit`.
    static func refs(for query: PhotoQuery, limit: Int = 200) async -> [PhotoRef] {
        await Task.detached(priority: .utility) {
            let assets = fetch(query, limit: limit)
            return assets.map { PhotoRef(source: .library(localIdentifier: $0.localIdentifier), date: $0.creationDate) }
        }.value
    }

    /// Regular albums and iCloud Shared Albums that contain photos.
    static func albums() async -> [PhotoAlbum] {
        await Task.detached(priority: .userInitiated) {
            var albums: [PhotoAlbum] = []
            for subtype in [PHAssetCollectionSubtype.albumCloudShared, .albumRegular] {
                let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
                collections.enumerateObjects { collection, _, _ in
                    let count = PHAsset.fetchAssets(in: collection, options: imageOptions(limit: 0)).count
                    guard count > 0 else { return }
                    albums.append(PhotoAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? "Untitled",
                                             count: count, isShared: subtype == .albumCloudShared))
                }
            }
            return albums
        }.value
    }

    /// A photo's size in pixels, upright, without loading it.
    static func pixelSize(localIdentifier: String) -> CGSize? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject,
              asset.pixelWidth > 0, asset.pixelHeight > 0 else { return nil }
        return CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
    }

    /// Loads a photo upright, at most `maxPixel` on its longest side.
    /// Downloads from iCloud when needed (shared albums usually need it).
    static func image(localIdentifier: String, maxPixel: Int) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    log.error("Photo load failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return downsample(data, maxPixel: maxPixel)
    }

    /// Decodes image data straight to a small, correctly rotated bitmap.
    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: Queries

    private static func fetch(_ query: PhotoQuery, limit: Int) -> [PHAsset] {
        switch query.source {
        case .library:
            return library(limit: limit)
        case .favorites:
            return smartAlbum(.smartAlbumFavorites, limit: limit)
        case .portraits:
            return smartAlbum(.smartAlbumDepthEffect, limit: limit)
        case .album:
            guard let albumID = query.albumID,
                  let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject
            else { return [] }
            return array(PHAsset.fetchAssets(in: collection, options: imageOptions(limit: limit)))
        case .picked:
            return array(PHAsset.fetchAssets(withLocalIdentifiers: query.pickedIDs, options: nil))
        case .single:
            guard let id = query.singleID else { return [] }
            return array(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil))
        case .featured:
            return featured(limit: limit)
        }
    }

    /// The photos in one of the system's smart albums, such as Favorites or Portrait.
    private static func smartAlbum(_ subtype: PHAssetCollectionSubtype, limit: Int) -> [PHAsset] {
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
        guard let collection = albums.firstObject else { return [] }
        return array(PHAsset.fetchAssets(in: collection, options: imageOptions(limit: limit)))
    }

    /// The newest photos in the whole library (Recents in the system Photos
    /// app), without screenshots, which rarely belong in a photo frame.
    private static func library(limit: Int) -> [PHAsset] {
        let options = imageOptions(limit: limit)
        options.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) == 0",
            PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        return array(PHAsset.fetchAssets(with: options))
    }

    /// PhotoKit has no "Featured Photos" album, so this approximates it:
    /// Portrait mode photos and favorites from the last two years, or recent
    /// photos (without screenshots) when there are too few of those.
    private static func featured(limit: Int) -> [PHAsset] {
        let since = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? .distantPast
        let options = imageOptions(limit: limit)
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate > %@ AND ((mediaSubtypes & %d) != 0 OR favorite == YES)",
            PHAssetMediaType.image.rawValue, since as NSDate, PHAssetMediaSubtype.photoDepthEffect.rawValue
        )
        let picks = array(PHAsset.fetchAssets(with: options))
        if picks.count >= 12 { return picks }
        let recent = imageOptions(limit: limit)
        recent.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) == 0",
            PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        return picks + array(PHAsset.fetchAssets(with: recent)).filter { asset in !picks.contains(asset) }
    }

    private static func imageOptions(limit: Int) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        return options
    }

    private static func array(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
}
