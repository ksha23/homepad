import AVFoundation
import Foundation
import HomePadCore
import Observation
import Photos
import UIKit

/// The iPad's photo library, favorites, albums and iCloud Shared Albums.
///
/// `albums` holds every album, for the slideshow and the Photo widget, which
/// are picture frames. The Photos app shows `albums(for:)`, what the person
/// at the screen may see (`PhotoAccessPolicy`). On the iPad that shows
/// HomePad, photo sync (`startSyncing()`, `sync(_:)`) keeps the albums current
/// from launch, so opening Photos shows new photos at once.
@MainActor
@Observable
public final class PhotoLibraryService {
    public internal(set) var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Albums in the order the Photos app shows them, the library first.
    public private(set) var albums: [PhotoAlbum] = []
    /// False until the album list has been read once, so views can tell
    /// "still loading" from "no photos".
    public private(set) var hasLoaded = false
    /// Goes up whenever the albums are read again, for example after the
    /// library changed, so views showing photos can refresh.
    public private(set) var revision = 0

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let household: Household
    @ObservationIgnored let imageManager = PHCachingImageManager()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: LibraryChangeObserver?
    /// The length of each video seen in an album, by local identifier. Filled
    /// as albums load, so grid cells can badge videos without asking PhotoKit.
    @ObservationIgnored private var videoDurations: [String: TimeInterval] = [:]
    /// Width over height of photos laid out so far, by local identifier.
    @ObservationIgnored private var aspectRatios: [String: CGFloat] = [:]
    /// Called after the albums changed because the library did, so photo sync
    /// can prepare what is new.
    @ObservationIgnored var onAlbumsChanged: (() -> Void)?
    /// Photo counts per album at the last sync, to find the albums that gained photos.
    @ObservationIgnored var syncedCounts: [String: Int] = [:]

    public init(settings: SettingsStore, household: Household) {
        self.settings = settings
        self.household = household
        let center = NotificationCenter.default
        // Access can change in the Settings app while HomePad runs.
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfAccessChanged() }
        }
        // Prepared pictures are only a head start, so they go first when memory runs low.
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.imageManager.stopCachingImagesForAllAssets() }
        }
    }

    /// The albums the person at the screen may see, for the Photos app.
    public func albums(for access: PhotoAccessPolicy) -> [PhotoAlbum] {
        PhotoAlbumRules.visible(albums, to: access)
    }

    public var isUsingDemoData: Bool { settings[PersonalSettings.demoData] }

    /// True when photos can be shown (demo data counts).
    public var canShowPhotos: Bool {
        isUsingDemoData || authorization == .authorized || authorization == .limited
    }

    /// True when the person said no, so the app should point to Settings.
    public var isDenied: Bool {
        !isUsingDemoData && (authorization == .denied || authorization == .restricted)
    }

    /// True when the person allowed only some photos.
    public var isLimited: Bool {
        !isUsingDemoData && authorization == .limited
    }

    /// Shows the system prompt. Call only after the person tapped a button that explains why.
    public func requestAccess() async {
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        reload()
    }

    /// Shows the system sheet for choosing which photos HomePad may see.
    /// Only meaningful with limited access.
    public func chooseAllowedPhotos() {
        guard isLimited, let presenter = UIApplication.shared.topViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Reads the album list again, off the main thread. Background work reads
    /// at a lower priority than a screen waiting for it.
    public func reload(priority: TaskPriority = .userInitiated) {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        loadTask?.cancel()
        if isUsingDemoData {
            finishLoading(DemoPhotos.albums)
            return
        }
        guard canShowPhotos else {
            finishLoading([])
            return
        }
        observeLibraryChanges()
        let picked = settings[PersonalSettings.photoSources].pickedPhotoIDs
        loadTask = Task {
            let fetched = await Task.detached(priority: priority) { PhotoKitQueries.albums(pickedIDs: picked) }.value
            guard !Task.isCancelled else { return }
            finishLoading(fetched)
        }
    }

    /// Reads the album list again and waits for it, for photo sync.
    func reloadAndWait(priority: TaskPriority) async {
        reload(priority: priority)
        await loadTask?.value
    }

    /// Reads the album list the first time a view needs it.
    public func loadIfNeeded() {
        if !hasLoaded, loadTask == nil { reload() }
    }

    // MARK: Photos

    /// Photos in one album, newest first, with its videos too unless
    /// `includesVideos` is false. Only the Photos app shows videos. The
    /// slideshow, the Photo widget and the faces take photos. Fetched off the
    /// main thread, because the library can hold tens of thousands of photos.
    public func photos(in album: PhotoAlbum, includesVideos: Bool = true, priority: TaskPriority = .userInitiated) async -> [PhotoRef] {
        if isUsingDemoData { return DemoPhotos.photos(in: album.id) }
        switch album.kind {
        case .picked:
            let picked = settings[PersonalSettings.photoSources].pickedPhotoIDs
            let ids = await Task.detached(priority: priority) { PhotoKitQueries.existingAssetIDs(picked) }.value
            return ids.map(PhotoRef.library)
        case .demo:
            return []
        default:
            let collectionID = album.id
            let assets = await Task.detached(priority: priority) {
                PhotoKitQueries.assets(inCollection: collectionID, includesVideos: includesVideos)
            }.value
            for asset in assets {
                if let duration = asset.videoDuration { videoDurations[asset.id] = duration }
            }
            return assets.map { PhotoRef.library($0.id) }
        }
    }

    /// Width over height, for laying a photo out before its image arrives. Demo
    /// photos are 4:3, with every third one upright.
    public func aspectRatio(for photo: PhotoRef) -> CGFloat {
        switch photo {
        case .demo(let index):
            return index % 3 == 2 ? 3.0 / 4.0 : 4.0 / 3.0
        case .phone(let photo):
            return CGFloat(photo.aspectRatio)
        case .library(let id):
            if let known = aspectRatios[id] { return known }
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                  asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 4.0 / 3.0 }
            let ratio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
            aspectRatios[id] = ratio
            return ratio
        }
    }

    /// Starts loading photos into the image cache, at the size `image(for:targetSize:)`
    /// will ask for, so they show at once when someone pages to them.
    public func prefetch(_ photos: [PhotoRef], targetSize: CGSize) {
        let ids = photos.compactMap { photo -> String? in
            if case .library(let id) = photo { return id }
            return nil
        }
        guard !ids.isEmpty else { return }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let assets = (0..<fetched.count).map { fetched.object(at: $0) }
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: Self.displayOptions)
    }

    /// The length of a video, or nil for a photo.
    public func videoDuration(for photo: PhotoRef) -> TimeInterval? {
        guard case .library(let id) = photo else { return nil }
        return videoDurations[id]
    }

    /// A library video ready to play. Allows iCloud downloads, which shared
    /// albums always need.
    public func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              asset.mediaType == .video else { return nil }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            imageManager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    /// Photos for the slideshow and the Photo widget, from the sources in
    /// Settings, without repeats. `PhotoAlbumRules.slideshowSources` says which.
    /// The Photos app passes the viewer's `access`, and the widget none.
    public func slideshowPhotos(access: PhotoAccessPolicy? = nil) async -> [PhotoRef] {
        if isUsingDemoData, access?.allowsLibrary != false { return DemoPhotos.all }
        loadIfNeeded()
        await loadTask?.value
        let sources = PhotoAlbumRules.slideshowSources(albums, selection: settings[PersonalSettings.photoSources], access: access)
        var seen = Set<PhotoRef>()
        var result: [PhotoRef] = []
        for album in sources {
            for photo in await photos(in: album, includesVideos: false) where seen.insert(photo).inserted {
                result.append(photo)
            }
        }
        return result
    }

    /// Loads a library photo sized for display. Allows iCloud downloads, which
    /// shared albums always need.
    public func image(for id: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: Self.displayOptions) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// How photos load for display. Prefetching uses the same, so the cache serves them.
    nonisolated static var displayOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    // MARK: Picked photos (PhotosUI)

    /// Stores photos chosen with the system photo picker as their own source.
    public func setPickedPhotos(_ identifiers: [String]) {
        settings[PersonalSettings.photoSources].pickedPhotoIDs = identifiers
        reload()
    }

    // MARK: Private

    private func finishLoading(_ fetched: [PhotoAlbum]) {
        let arranged = PhotoAlbumRules.arranged(fetched)
        let changed = hasLoaded && arranged != albums
        albums = arranged
        hasLoaded = true
        revision += 1
        if changed { onAlbumsChanged?() }
    }

    private func reloadIfAccessChanged() {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) != authorization { reload() }
    }

    /// Watches the library once access is granted, so new photos in a shared
    /// album or a new selection under limited access show up without a relaunch.
    func observeLibraryChanges() {
        guard changeObserver == nil else { return }
        let observer = LibraryChangeObserver { [weak self] in self?.libraryDidChange() }
        PHPhotoLibrary.shared().register(observer)
        changeObserver = observer
    }

    /// iCloud can report many changes in a row, so this waits for a quiet
    /// second. Nobody waits for this read, so it runs at background priority.
    private func libraryDidChange() {
        changeTask?.cancel()
        changeTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            reload(priority: BackgroundWork.priority)
        }
    }
}

/// Forwards PhotoKit change notifications to the main actor.
private final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @MainActor @Sendable () -> Void

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in onChange() }
    }
}

private extension UIApplication {
    /// The view controller on top in the active window, to present UIKit sheets from.
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
