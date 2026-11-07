import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps Vision subject masks on disk (small grayscale PNGs in Caches), so a
/// photo is segmented once even across launches. Masks are not personal
/// data beyond the photo itself and the system may purge Caches at any time.
struct MaskDiskCache: Sendable {
    private let directory: URL?

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let directory = caches?.appendingPathComponent("FacesDepthMasks", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.directory = directory
    }

    func mask(for key: String) -> CGImage? {
        guard let url = url(for: key),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func store(_ mask: CGImage, for key: String) {
        guard let url = url(for: key),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, mask, nil)
        CGImageDestinationFinalize(destination)
    }

    /// File names are hashes, so photo identifiers never appear on disk.
    private func url(for key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("\(digest).png")
    }
}
