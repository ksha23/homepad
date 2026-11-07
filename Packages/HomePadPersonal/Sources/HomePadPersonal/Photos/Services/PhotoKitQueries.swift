import Foundation
import Photos

/// The PhotoKit fetches behind `PhotoLibraryService`. PhotoKit is safe to use
/// from any thread, so these run off the main thread, where a library of tens
/// of thousands of photos cannot stall the screen.
enum PhotoKitQueries {
    /// Every album HomePad can show, in PhotoKit's order. `PhotoAlbumRules`
    /// arranges them. With limited access each album holds only the photos
    /// the person allowed.
    static func albums(pickedIDs: [String]) -> [PhotoAlbum] {
        var result: [PhotoAlbum] = []
        let smartAlbums: [(PHAssetCollectionSubtype, PhotoAlbum.Kind, String)] = [
            (.smartAlbumUserLibrary, .library, "Library"),
            (.smartAlbumFavorites, .favorites, "Favorites"),
        ]
        for (subtype, kind, title) in smartAlbums {
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            if let collection = collections.firstObject {
                result.append(album(from: collection, kind: kind, title: title))
            }
        }
        let picked = existingAssetIDs(pickedIDs)
        if !picked.isEmpty {
            result.append(PhotoAlbum(id: "picked", title: "Selected Photos", kind: .picked, count: picked.count,
                                     keyPhoto: picked.first.map(PhotoRef.library)))
        }
        let albumKinds: [(PHAssetCollectionSubtype, PhotoAlbum.Kind)] = [(.albumCloudShared, .shared), (.albumRegular, .user)]
        for (subtype, kind) in albumKinds {
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in result.append(album(from: collection, kind: kind)) }
        }
        return result
    }


    /// The identifiers that still name a photo HomePad can read, in the order given.
    static func existingAssetIDs(_ identifiers: [String]) -> [String] {
        guard !identifiers.isEmpty else { return [] }
        var found = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil).enumerateObjects { asset, _, _ in
            found.insert(asset.localIdentifier)
        }
        return identifiers.filter(found.contains)
    }

    private static func album(from collection: PHAssetCollection, kind: PhotoAlbum.Kind, title: String? = nil) -> PhotoAlbum {
        let cover = assetIDs(in: collection, limit: 1)
        let count = PHAsset.fetchAssets(in: collection, options: options(for: [.image])).count
        let videoCount = PHAsset.fetchAssets(in: collection, options: options(for: [.video])).count
        return PhotoAlbum(id: collection.localIdentifier, title: title ?? collection.localizedTitle ?? "Album", kind: kind,
                          count: count, videoCount: videoCount, keyPhoto: cover.first.map(PhotoRef.library))
    }

    /// A library item, and its length when it is a video.
    struct AssetInfo: Sendable {
        let id: String
        let videoDuration: TimeInterval?
    }

    /// Photos in a collection, and videos too when asked, newest first.
    static func assets(inCollection identifier: String, includesVideos: Bool) -> [AssetInfo] {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return [] }
        return assets(in: collection, types: includesVideos ? [.image, .video] : [.image])
    }

    private static func assetIDs(in collection: PHAssetCollection, limit: Int = 0) -> [String] {
        assets(in: collection, types: [.image], limit: limit).map(\.id)
    }

    private static func assets(in collection: PHAssetCollection, types: [PHAssetMediaType], limit: Int = 0) -> [AssetInfo] {
        let options = options(for: types)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let fetched = PHAsset.fetchAssets(in: collection, options: options)
        var result: [AssetInfo] = []
        result.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in
            result.append(AssetInfo(id: asset.localIdentifier, videoDuration: asset.mediaType == .video ? asset.duration : nil))
        }
        return result
    }

    private static func options(for types: [PHAssetMediaType]) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType IN %@", types.map(\.rawValue))
        return options
    }
}
