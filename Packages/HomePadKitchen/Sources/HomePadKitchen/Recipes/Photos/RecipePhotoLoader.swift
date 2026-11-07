import Foundation
import ImageIO
import Observation
import UIKit

/// Loads recipe photos once. Web photos come through a disk cache that keeps
/// them across launches, so the Discover shelf, search results and the library
/// do not download the same photo again. Every photo, web or picked on this
/// iPad, is decoded off the main thread at the size it is shown and kept in
/// memory, so a shelf that scrolls or a grid that redraws never decodes it again.
@MainActor
@Observable
final class RecipePhotoLoader {
    static let shared = RecipePhotoLoader()

    /// One photo at one display size.
    struct Key: Hashable, Sendable {
        let url: URL
        /// The longest side in pixels, one of `sizes`.
        let pixels: Int
        /// Goes up when a picked photo is replaced, since its file name stays the same.
        let revision: Int
    }

    /// Goes up for a file each time `forget` replaces it, so views showing it load it again.
    private(set) var revisions: [URL: Int] = [:]

    @ObservationIgnored private let memory = NSCache<NSString, UIImage>()
    @ObservationIgnored private var loading: [Key: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private let session: URLSession

    /// Decoded sizes, so a photo shown at about the same size is decoded once. The
    /// largest is a 13-inch iPad's long side, for the recipe card's full-screen photo.
    static let sizes = [256, 512, 1024, 2048, 2732]

    init() {
        memory.totalCostLimit = 96 * 1024 * 1024
        let folder = URL.cachesDirectory.appending(path: "RecipePhotos", directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 150 * 1024 * 1024, directory: folder)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    /// The key for a photo shown `points` long on a screen with `scale` pixels per point.
    func key(for url: URL, points: CGFloat, scale: CGFloat) -> Key {
        let needed = Int((points * scale).rounded(.up))
        let pixels = Self.sizes.first { $0 >= needed } ?? Self.sizes[Self.sizes.count - 1]
        return Key(url: url, pixels: pixels, revision: revisions[url] ?? 0)
    }

    /// The photo, when it was already decoded at this size.
    func cached(_ key: Key) -> UIImage? {
        memory.object(forKey: key.cacheName)
    }

    /// Downloads or reads the photo, decodes it at the key's size and keeps it.
    /// Nil when it cannot be loaded. Several views asking at once share one load.
    func photo(_ key: Key) async -> UIImage? {
        if let image = cached(key) { return image }
        if let running = loading[key] { return await running.value }
        let session = session
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = await Self.data(at: key.url, session: session) else { return nil }
            return Self.decode(data, maxPixels: key.pixels)
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image {
            memory.setObject(image, forKey: key.cacheName, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    /// Drops what is kept for a file that was just replaced, such as a picked
    /// photo saved again under the same name.
    func forget(_ url: URL) {
        revisions[url, default: 0] += 1
    }

    // MARK: Loading

    private nonisolated static func data(at url: URL, session: URLSession) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url) }
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return data
    }

    /// Decodes at most `maxPixels` on the longest side, upright, ready to draw.
    private nonisolated static func decode(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }
}

private extension RecipePhotoLoader.Key {
    var cacheName: NSString { "\(revision)|\(pixels)|\(url.absoluteString)" as NSString }
}
