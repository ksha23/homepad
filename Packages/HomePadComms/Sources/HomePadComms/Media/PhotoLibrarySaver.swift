import Foundation
import Photos

/// Adds photos and videos to the Photos library. It asks only for add access,
/// so HomePad never reads what is already in the library.
enum PhotoLibrarySaver {
    struct Item {
        var data: Data
        var filename: String
        var isVideo: Bool
    }

    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            "HomePad is not allowed to add to Photos. Allow it under Settings > Privacy & Security > Photos."
        }
    }

    static func save(_ items: [Item]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }

        // Photos reads a video from a file. It is written here and deleted right after.
        var videoFiles: [URL] = []
        defer { for file in videoFiles { try? FileManager.default.removeItem(at: file) } }
        var staged: [(Item, URL?)] = []
        for item in items {
            guard item.isVideo else { staged.append((item, nil)); continue }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + item.filename)
            try item.data.write(to: file, options: [.atomic, .completeFileProtection])
            videoFiles.append(file)
            staged.append((item, file))
        }

        try await PHPhotoLibrary.shared().performChanges {
            for (item, file) in staged {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = item.filename
                let request = PHAssetCreationRequest.forAsset()
                if let file {
                    request.addResource(with: .video, fileURL: file, options: options)
                } else {
                    request.addResource(with: .photo, data: item.data, options: options)
                }
            }
        }
    }
}
