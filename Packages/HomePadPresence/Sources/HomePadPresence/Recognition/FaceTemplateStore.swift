import Foundation

/// Stores face templates, and the samples learned from use, on this iPad only.
///
/// - Lives in Application Support, never in iCloud Drive or CloudKit.
/// - The folder is excluded from iCloud and device backups.
/// - Each file is written with complete file protection, so it is encrypted
///   and unreadable while the iPad is locked.
struct FaceTemplateStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/HomePadPresence/FaceTemplates`.
    static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("HomePadPresence/FaceTemplates", isDirectory: true)
    }

    func loadAll() throws -> [FaceTemplate] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            try? decoder.decode(FaceTemplate.self, from: Data(contentsOf: url))
        }
    }

    func save(_ template: FaceTemplate) throws {
        try prepareDirectory(directory)
        let data = try JSONEncoder().encode(template)
        try data.write(to: fileURL(for: template.memberID), options: [.atomic, .completeFileProtection])
    }

    /// Deletes a member's face data: the enrolled template, what was learned
    /// and their depth templates.
    func delete(memberID: UUID) throws {
        try deleteLearned(memberID: memberID)
        try deleteDepth(memberID: memberID)
        try removeIfPresent(fileURL(for: memberID))
    }

    /// Gives a member's face data a new member ID: the enrolled template, what
    /// was learned and the depth templates are written under the new ID, then
    /// the old files go. It all stays in this folder, on this iPad.
    func move(from old: UUID, to new: UUID) throws {
        let decoder = JSONDecoder()
        if FileManager.default.fileExists(atPath: fileURL(for: old).path) {
            var template = try decoder.decode(FaceTemplate.self, from: Data(contentsOf: fileURL(for: old)))
            template.memberID = new
            try save(template)
        }
        if FileManager.default.fileExists(atPath: learnedFileURL(for: old).path) {
            var learned = try decoder.decode(LearnedFaceSamples.self, from: Data(contentsOf: learnedFileURL(for: old)))
            learned.memberID = new
            try saveLearned(learned)
        }
        try moveDepth(from: old, to: new)
        try delete(memberID: old)
    }

    // MARK: Learned samples

    /// Embeddings learned from use (`LearnedFaceSamples`) live in their own
    /// files in `Learned/`, so learning never rewrites an enrolled template.
    /// The folder has no `.json` extension, so `loadAll()` skips it, as it
    /// does `Depth/` (`FaceTemplateStore+Depth`).
    var learnedDirectory: URL { directory.appendingPathComponent("Learned", isDirectory: true) }

    func loadLearned() throws -> [LearnedFaceSamples] {
        guard FileManager.default.fileExists(atPath: learnedDirectory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: learnedDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            try? decoder.decode(LearnedFaceSamples.self, from: Data(contentsOf: url))
        }
    }

    func saveLearned(_ learned: LearnedFaceSamples) throws {
        try prepareDirectory(directory)
        try prepareDirectory(learnedDirectory)
        let data = try JSONEncoder().encode(learned)
        try data.write(to: learnedFileURL(for: learned.memberID), options: [.atomic, .completeFileProtection])
    }

    func deleteLearned(memberID: UUID) throws {
        try removeIfPresent(learnedFileURL(for: memberID))
    }

    private func fileURL(for memberID: UUID) -> URL {
        directory.appendingPathComponent("\(memberID.uuidString).json")
    }

    private func learnedFileURL(for memberID: UUID) -> URL {
        learnedDirectory.appendingPathComponent("\(memberID.uuidString).json")
    }

    func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func prepareDirectory(_ folder: URL) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
