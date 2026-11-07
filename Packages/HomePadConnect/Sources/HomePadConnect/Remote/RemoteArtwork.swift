import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How a cover reaches a companion. A web cover goes as its address and the
/// companion loads it. A cover in a file on the HomePad (generated or cached art)
/// goes as a small JPEG attached to the `media.status` message.
enum RemoteArtwork {
    /// Longest side of an attached cover, enough for a phone's full-width artwork.
    static let attachedPixels = 600

    /// The web image behind a cover address. Apple Music covers use `musicKit://`
    /// addresses that carry the catalog image's web address (`aat` or `fat`).
    /// Nil when there is no web image.
    static func webURL(for url: URL?) -> URL? {
        guard let url else { return nil }
        if isWeb(url) { return url }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["aat", "fat"] {
            if let value = items.first(where: { $0.name == name })?.value, let web = URL(string: value), isWeb(web) {
                return web
            }
        }
        return nil
    }

    /// A short stable name for a cover the companion can show, nil for one it cannot.
    /// A hash, so file paths on the HomePad never travel.
    static func key(for url: URL?) -> String? {
        guard let url, webURL(for: url) != nil || url.isFileURL else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// True for a cover that has to travel as an attachment.
    static func needsAttachment(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.isFileURL && webURL(for: url) == nil
    }

    /// The cover file scaled down to `attachedPixels` and encoded as JPEG. Runs off the main actor.
    static func attachment(from file: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: attachedPixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }.value
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}
