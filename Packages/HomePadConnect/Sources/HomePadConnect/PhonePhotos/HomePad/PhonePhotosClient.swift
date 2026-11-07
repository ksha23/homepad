import Foundation
import HomePadCore
import Observation

/// On a HomePad: the recognized person's own iPhone photos, one kind of data
/// a phone visit carries (`PhoneVisitClient`). Installed as `services.phonePhotos`.
///
/// When a visit opens the phone's photos, this fetches the album list,
/// Recents and Favorites with thumbnails first, saving them in the member's
/// encrypted cache. `library` appears once the phone has opened its photos
/// during the visit, and is gone, with everything held in memory, the moment
/// the person stops being recognized.
@MainActor
@Observable
public final class PhonePhotosClient: PhonePhotosService, PhoneVisitPart {
    public private(set) var library: PhoneLibrary?

    let kinds: Set<PhoneDataKind> = [.photos]
    @ObservationIgnored let visits: PhoneVisitClient
    @ObservationIgnored var cache = PhonePhotosCache()
    /// Every write to the cache, in order, so a save never lands after the
    /// delete that forgets a person.
    @ObservationIgnored let cacheQueue = DispatchQueue(label: "com.ksha23.homepad.phonephotos.cache", qos: .utility)
    /// What this visit holds of the person's photos.
    @ObservationIgnored var state: PhotoVisitState?
    @ObservationIgnored let log = Log.make("PhonePhotos")

    init(visits: PhoneVisitClient) {
        self.visits = visits
    }

    func start() {
        registerHandlers()
    }

    /// Linked phones that share something, by device ID.
    var sharedPhones: [String: SharedPhone] { visits.sharedPhones }

    // MARK: PhonePhotosService

    public func photos(in album: PhoneAlbum) async -> [PhonePhoto] {
        guard let state, library != nil else { return [] }
        let visit = state.visit
        if state.freshLists.contains(album.id), let list = state.index.lists[album.id] { return list }
        if let reply = await request(.photos(in: album.id), in: visit), let photos = reply.photos {
            guard let state = current(visit) else { return [] }
            state.index.lists[album.id] = photos
            state.freshLists.insert(album.id)
            saveIndex(of: state)
            return photos
        }
        return current(visit)?.index.lists[album.id] ?? []
    }

    public func thumbnail(of photo: PhonePhoto.ID) async -> Data? {
        await image(photo, size: .thumbnail)
    }

    public func fullImage(of photo: PhonePhoto.ID) async -> Data? {
        await image(photo, size: .screen)
    }

    // MARK: PhoneVisitPart

    /// Loads what was saved, which shows once the phone opens its photos.
    func visitStarted(_ visit: PhoneVisit) {
        let index = cache.loadIndex(member: visit.memberID)
            ?? PhoneLibraryIndex(deviceName: visit.deviceName, albums: [], lists: [:], savedAt: visits.now())
        state = PhotoVisitState(visit: visit, index: index)
    }

    /// What a visit fetches first, inside the few seconds a woken phone runs:
    /// the albums, Recents and Favorites, then their thumbnails newest first,
    /// then a few full images of the newest photos.
    func prefetch(_ visit: PhoneVisit) async {
        guard current(visit) != nil else { return }
        if let albums = await request(.albumList(), in: visit)?.albums, let state = current(visit) {
            state.index.albums = albums
            state.index.deviceName = visit.deviceName
            publish(visit)
        }
        for album in current(visit)?.index.albums ?? [] where album.kind != .album {
            _ = await photos(in: album)
        }
        guard let state = current(visit) else { return }
        saveIndex(of: state)
        let covers = state.index.albums.compactMap(\.keyPhoto?.id)
        let recents = state.list(of: .recents).map(\.id)
        let favorites = state.list(of: .favorites).map(\.id)
        let wanted = Self.unique(covers + recents.prefix(90) + favorites.prefix(45))
        await fetchMissing(wanted, size: .thumbnail, in: state)
        await fetchMissing(Array(recents.prefix(6)), size: .screen, in: state)
        guard current(visit) != nil else { return }
        let member = visit.memberID
        writeCache { $0.trim(member: member) }
    }

    /// Shows the library once the phone opened its photos during this visit.
    func publish(_ visit: PhoneVisit) {
        guard let state = current(visit), visit.hasAnswered, visit.grantedKinds.contains(.photos) else { return }
        let library = PhoneLibrary(memberID: visit.memberID, deviceName: visit.deviceName,
                                   albums: state.index.albums, isConnected: visits.isConnected(visit))
        if self.library != library { self.library = library }
    }

    /// Photos ask for what they miss as they are drawn, so nothing waits for the phone.
    func phoneConnected(_ visit: PhoneVisit) {}

    /// Nothing of the person stays in memory.
    func visitEnded(_ visit: PhoneVisit) {
        guard let state, state.visit === visit else { return }
        self.state = nil
        library = nil
        state.finish()
    }

    /// Removes a person's cache once every write before it is done.
    func forget(_ member: UUID, keeping kinds: Set<PhoneDataKind>) {
        let cache = cache
        cacheQueue.sync { cache.delete(member: member) }
    }

    func prune(keeping members: Set<UUID>) {
        let cache = cache
        cacheQueue.sync { cache.prune(keeping: members) }
    }

    /// This visit's photos while it is the one on.
    func current(_ visit: PhoneVisit) -> PhotoVisitState? {
        guard let state, state.visit === visit, visits.isCurrent(visit) else { return nil }
        return state
    }

    // MARK: Images

    /// An image from this visit's memory, the member's cache, or the phone.
    private func image(_ photoID: String, size: PhotoImageSize) async -> Data? {
        guard let state, library != nil else { return nil }
        if let held = state.images[PhotoVisitState.imageKey(photoID, size)] { return held }
        let visit = state.visit
        let member = visit.memberID
        let cache = cache
        let saved = await Task.detached(priority: .userInitiated) { cache.image(photoID, size: size, member: member) }.value
        guard let state = current(visit) else { return nil }
        if let saved {
            state.images[PhotoVisitState.imageKey(photoID, size)] = saved
            return saved
        }
        return await fetch(photoID, size: size, in: state)
    }

    /// Fetches the images the cache lacks, a batch at a time.
    private func fetchMissing(_ ids: [String], size: PhotoImageSize, in state: PhotoVisitState) async {
        let member = state.visit.memberID
        let cache = cache
        let missing = await Task.detached(priority: .utility) { ids.filter { cache.image($0, size: size, member: member) == nil } }.value
        for batch in stride(from: 0, to: missing.count, by: PhonePhotosPolicy.imagesPerRequest) {
            guard current(state.visit) === state else { return }
            let ids = Array(missing[batch..<min(batch + PhonePhotosPolicy.imagesPerRequest, missing.count)])
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { @MainActor in _ = await self.fetch(id, size: size, in: state) }
                }
            }
        }
    }

    private func saveIndex(of state: PhotoVisitState) {
        var stamped = state.index
        stamped.savedAt = visits.now()
        let index = stamped
        let member = state.visit.memberID
        writeCache { $0.saveIndex(index, member: member) }
    }

    /// Queues a write behind every earlier one.
    func writeCache(_ write: @escaping @Sendable (PhonePhotosCache) -> Void) {
        let cache = cache
        cacheQueue.async { write(cache) }
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// On a HomePad: what one visit holds of a person's photos. Everything here
/// lives only as long as the visit.
@MainActor
final class PhotoVisitState {
    let visit: PhoneVisit
    var index: PhoneLibraryIndex
    /// Albums whose photos the phone listed during this visit.
    var freshLists: Set<String> = []
    /// Images held for this visit, by `imageKey`.
    var images: [String: Data] = [:]
    var imageWaiters: [String: [UUID: CheckedContinuation<Data?, Never>]] = [:]
    /// Images asked for and not yet sent, so a grid's many cells go in one request.
    var queued: [PhotoImageSize: [String]] = [:]
    var flushScheduled = false

    init(visit: PhoneVisit, index: PhoneLibraryIndex) {
        self.visit = visit
        self.index = index
    }

    static func imageKey(_ photoID: String, _ size: PhotoImageSize) -> String { "\(size.rawValue)|\(photoID)" }

    /// The photos listed for the album of that kind.
    func list(of kind: PhoneAlbum.Kind) -> [PhonePhoto] {
        guard let album = index.albums.first(where: { $0.kind == kind }) else { return [] }
        return index.lists[album.id] ?? []
    }

    /// Lets everyone waiting go with nothing and forgets what was held.
    func finish() {
        imageWaiters.values.flatMap(\.values).forEach { $0.resume(returning: nil) }
        imageWaiters = [:]
        queued = [:]
        images = [:]
    }
}
