import Foundation

/// Depth templates (`MemberDepthTemplates`) live in `FaceTemplates/Depth/`,
/// one file per member, with the same protection as the face templates:
/// complete file protection, excluded from backups, never in iCloud. They are
/// deleted and moved with the member's other face data.
extension FaceTemplateStore {
    var depthDirectory: URL { directory.appendingPathComponent("Depth", isDirectory: true) }

    func loadDepth() throws -> [MemberDepthTemplates] {
        guard FileManager.default.fileExists(atPath: depthDirectory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: depthDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            try? decoder.decode(MemberDepthTemplates.self, from: Data(contentsOf: url))
        }
    }

    func saveDepth(_ templates: MemberDepthTemplates) throws {
        try prepareDirectory(directory)
        try prepareDirectory(depthDirectory)
        let data = try JSONEncoder().encode(templates)
        try data.write(to: depthFileURL(for: templates.memberID), options: [.atomic, .completeFileProtection])
    }

    func deleteDepth(memberID: UUID) throws {
        try removeIfPresent(depthFileURL(for: memberID))
    }

    /// Rewrites a member's depth templates under a new member ID, then deletes the old file.
    func moveDepth(from old: UUID, to new: UUID) throws {
        let url = depthFileURL(for: old)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var templates = try JSONDecoder().decode(MemberDepthTemplates.self, from: Data(contentsOf: url))
        templates.memberID = new
        try saveDepth(templates)
        try deleteDepth(memberID: old)
    }

    private func depthFileURL(for memberID: UUID) -> URL {
        depthDirectory.appendingPathComponent("\(memberID.uuidString).json")
    }
}
