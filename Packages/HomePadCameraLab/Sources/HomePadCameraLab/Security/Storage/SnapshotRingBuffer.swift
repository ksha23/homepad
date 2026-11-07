import Foundation

/// One saved motion snapshot.
struct MotionSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var personDetected: Bool
    /// File name inside the ring buffer's directory.
    var fileName: String
}

/// Keeps the most recent motion snapshots on this iPad (never in iCloud).
/// The oldest files are deleted once `limit` is reached.
@MainActor
final class SnapshotRingBuffer {
    let directory: URL
    var limit: Int {
        didSet { trim() }
    }
    private(set) var snapshots: [MotionSnapshot] = []
    private let fileManager = FileManager.default
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    /// The default location under Application Support, excluded from backups.
    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CameraLab/MotionSnapshots", isDirectory: true)
    }

    init(directory: URL = SnapshotRingBuffer.defaultDirectory, limit: Int) {
        self.directory = directory
        self.limit = max(1, limit)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directoryURL = directory
        try? directoryURL.setResourceValues(values)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([MotionSnapshot].self, from: data) {
            snapshots = saved.filter { fileManager.fileExists(atPath: url(for: $0).path) }
        }
    }

    func url(for snapshot: MotionSnapshot) -> URL {
        directory.appendingPathComponent(snapshot.fileName)
    }

    /// Saves a JPEG and drops the oldest entries beyond the limit. Newest first.
    @discardableResult
    func add(jpeg: Data, date: Date = Date(), personDetected: Bool) throws -> MotionSnapshot {
        let id = UUID()
        let snapshot = MotionSnapshot(id: id, date: date, personDetected: personDetected, fileName: "\(id.uuidString).jpg")
        try jpeg.write(to: url(for: snapshot), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        snapshots.insert(snapshot, at: 0)
        trim()
        return snapshot
    }

    func removeAll() {
        for snapshot in snapshots { try? fileManager.removeItem(at: url(for: snapshot)) }
        snapshots.removeAll()
        saveIndex()
    }

    private func trim() {
        if snapshots.count > limit {
            for snapshot in snapshots[limit...] { try? fileManager.removeItem(at: url(for: snapshot)) }
            snapshots.removeSubrange(limit...)
        }
        saveIndex()
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
