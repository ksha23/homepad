import CryptoKit
import Foundation
import HomePadCore

/// What a HomePad keeps of one person's phone library between visits, so it
/// shows the moment their phone answers instead of after every thumbnail.
struct PhoneLibraryIndex: Codable, Equatable, Sendable {
    var deviceName: String
    var albums: [PhoneAlbum]
    /// Each album's photos, newest first, by album ID.
    var lists: [String: [PhonePhoto]]
    var savedAt: Date
}

/// On a HomePad: each person's phone photos, sealed per member
/// (`SealedMemberFiles`): one index, and one file per image. Thumbnails and
/// full images are capped, and the oldest go first.
struct PhonePhotosCache: Sendable {
    static let maxThumbnails = 800
    static let maxScreenImages = 60

    private let files: SealedMemberFiles

    init(directory: URL = PhonePhotosCache.defaultDirectory,
         keychain: any SecretStore = KeychainStore(service: "com.ksha23.homepad.phonephotos", synchronizable: false)) {
        files = SealedMemberFiles(directory: directory, keychain: keychain)
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("HomePadConnect/PhonePhotos", isDirectory: true)
    }

    // MARK: Index

    func loadIndex(member: UUID) -> PhoneLibraryIndex? {
        guard let plain = files.open("index.sealed", member: member) else { return nil }
        return try? Self.decoder.decode(PhoneLibraryIndex.self, from: plain)
    }

    @discardableResult
    func saveIndex(_ index: PhoneLibraryIndex, member: UUID) -> Bool {
        guard let plain = try? Self.encoder.encode(index) else { return false }
        return files.seal(plain, as: "index.sealed", member: member)
    }

    // MARK: Images

    func image(_ photoID: String, size: PhotoImageSize, member: UUID) -> Data? {
        files.open(imageName(photoID, size: size), member: member)
    }

    @discardableResult
    func saveImage(_ jpeg: Data, photoID: String, size: PhotoImageSize, member: UUID) -> Bool {
        files.seal(jpeg, as: imageName(photoID, size: size), member: member)
    }

    /// Removes the oldest images past the caps.
    func trim(member: UUID) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: files.folder(member), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        for size in [PhotoImageSize.thumbnail, .screen] {
            let cap = size == .thumbnail ? Self.maxThumbnails : Self.maxScreenImages
            let images = urls.filter { $0.lastPathComponent.hasPrefix(size.rawValue + "-") }
            guard images.count > cap else { continue }
            let oldestFirst = images.sorted { modified($0) < modified($1) }
            oldestFirst.prefix(images.count - cap).forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    // MARK: Forgetting

    /// Removes the member's key and folder.
    func delete(member: UUID) {
        files.delete(member: member)
    }

    /// Removes everyone not in `members`, for people removed from the household.
    func prune(keeping members: Set<UUID>) {
        files.prune(keeping: members)
    }

    // MARK: Plumbing

    /// The file name is a hash, so the folder does not list the phone's photo identifiers.
    private func imageName(_ photoID: String, size: PhotoImageSize) -> String {
        let digest = SHA256.hash(data: Data(photoID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(size.rawValue)-\(digest.prefix(32)).sealed"
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
