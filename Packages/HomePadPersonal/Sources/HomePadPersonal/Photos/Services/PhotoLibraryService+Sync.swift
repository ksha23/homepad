import HomePadCore
import Photos
import UIKit

/// Photo sync, the Personal module's background task.
///
/// HomePad cannot make iCloud Photos download anything. iOS's own photo
/// service does that on its own schedule. What HomePad can do is notice the
/// moment new photos land in the library, read the albums again and prepare
/// the pictures Photos opens on, so it shows them at once instead of reading
/// everything while someone waits.
extension PhotoLibraryService {
    /// What background work may read ahead: the sources some member of the
    /// household may see. Nothing for a household with nobody in it.
    var householdSources: Set<PhotoSource> {
        let owner = PhotoLibraryOwner.resolve(chosen: settings[PhotoLibraryOwner.setting], members: household.members)
        return PhotoAccessPolicy.householdSources(ownerID: owner)
    }

    /// Reads the albums and starts watching the library at launch, on the
    /// iPad that shows HomePad, instead of the first time Photos opens.
    func startSyncing() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard !isUsingDemoData, canShowPhotos, !householdSources.isEmpty else { return }
        reload(priority: BackgroundWork.priority)
    }

    /// Reads the albums again, then prepares every album's cover and the
    /// first screen of thumbnails of the library and of each album that
    /// gained photos since the last sync. Stops between albums when someone
    /// starts using the screen.
    func sync(_ context: BackgroundTaskContext) async -> BackgroundTaskOutcome {
        if isUsingDemoData { return .skipped("Demo photos stand in for this iPad's library.") }
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canShowPhotos else {
            return .skipped(isDenied ? "Photos access is off for HomePad." : "Photos access has not been allowed yet.")
        }
        guard !householdSources.isEmpty else { return .skipped("Nobody is set up in People yet, so nobody may see photos.") }
        await reloadAndWait(priority: BackgroundWork.priority)
        guard await context.checkpoint() else { return .stopped("Someone started using the screen.") }

        // The covers stay in step with the albums, and older pictures make room.
        imageManager.stopCachingImagesForAllAssets()
        let shown = albums
        var prepared = await prefetchInBackground(shown.compactMap(\.keyPhoto), targetSize: PhotoGridMetrics.coverPixels)
        let firstScreen = Self.screenSize.map(PhotoGridMetrics.firstScreenCount(on:)) ?? 0
        let grown = shown.filter { album in
            album.kind == .library || (!syncedCounts.isEmpty && album.count + album.videoCount > syncedCounts[album.id, default: 0])
        }
        for album in grown where firstScreen > 0 {
            guard await context.checkpoint() else { return .stopped("Someone started using the screen.") }
            let photos = await photos(in: album, priority: BackgroundWork.priority)
            prepared += await prefetchInBackground(Array(photos.prefix(firstScreen)), targetSize: PhotoGridMetrics.thumbnailPixels)
        }
        syncedCounts = Dictionary(shown.map { ($0.id, $0.count + $0.videoCount) }, uniquingKeysWith: max)
        let others = grown.filter { $0.kind != .library }.count
        let albumsText = others > 0 ? "the library and \(others) album\(others == 1 ? "" : "s") with new photos" : "the library"
        return .done("\(shown.count) albums read. \(prepared) pictures prepared: covers and the first screen of \(albumsText).")
    }

    /// Starts PhotoKit preparing these photos at the size the app asks for.
    /// The lookup runs off the main thread. The image manager is told on the
    /// main actor, where the app's own requests to it come from, and does the
    /// work on its own queues. Returns how many photos it started on.
    func prefetchInBackground(_ photos: [PhotoRef], targetSize: CGSize) async -> Int {
        let ids = photos.compactMap { photo -> String? in
            if case .library(let id) = photo { return id }
            return nil
        }
        guard !ids.isEmpty else { return 0 }
        let fetched = await Task.detached(priority: BackgroundWork.priority) {
            PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        }.value
        let assets = (0..<fetched.count).map { fetched.object(at: $0) }
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: Self.displayOptions)
        return assets.count
    }

    /// The screen HomePad shows on, nil while it has none (a background launch).
    private static var screenSize: CGSize? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.size }.first
    }
}
