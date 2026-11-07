import Photos
import UIKit

/// Saves timelapse frames into a named Photos album and reads them back.
enum PhotoAlbumLibrary {
    enum LibraryError: LocalizedError {
        case accessDenied
        case albumUnavailable

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Allow HomePad to add to Photos in Settings to save timelapse frames."
            case .albumUnavailable: "Could not create the timelapse album in Photos."
            }
        }
    }

    /// Asks for Photos access the first time a timelapse starts.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Adds one JPEG to the album, creating the album the first time.
    static func save(jpeg: Data, toAlbum title: String) async throws {
        guard hasAccess else { throw LibraryError.accessDenied }
        guard let album = try await album(titled: title, create: true) else { throw LibraryError.albumUnavailable }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpeg, options: nil)
            if let placeholder = request.placeholderForCreatedAsset {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }
    }

    /// The album's photos, oldest first.
    static func assets(inAlbum title: String) -> [PHAsset] {
        guard hasAccess, let album = existingAlbum(titled: title) else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(in: album, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private static func existingAlbum(titled title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }

    private static func album(titled title: String, create: Bool) async throws -> PHAssetCollection? {
        if let album = existingAlbum(titled: title) { return album }
        guard create else { return nil }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
        }
        return existingAlbum(titled: title)
    }
}
