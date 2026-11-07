import Foundation

/// A private folder where uploaded files wait for Messages.app to pick them up.
/// Each file gets its own folder so the original name survives. The folder is
/// owner-only and a file is deleted as soon as the send is done.
public struct Outbox: Sendable {
    public let directory: URL

    public init(directory: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.homepad-hub/outbox", isDirectory: true)) {
        self.directory = directory
    }

    /// Writes `data` as `filename` in a fresh folder and returns the file's address.
    public func stage(_ data: Data, filename: String) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(filename)
        guard fileManager.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            try? fileManager.removeItem(at: folder)
            throw CocoaError(.fileWriteUnknown)
        }
        return file
    }

    /// Deletes a staged file and its folder. Anything outside the outbox is left alone.
    public func discard(_ file: URL) {
        let folder = file.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent().path == directory.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes whatever an earlier run left behind.
    public func purge() {
        let fileManager = FileManager.default
        guard let leftovers = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for item in leftovers { try? fileManager.removeItem(at: item) }
    }
}
