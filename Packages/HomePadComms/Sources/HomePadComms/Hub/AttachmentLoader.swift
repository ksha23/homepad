import Foundation
import ImageIO
import UIKit

/// Loads and caches attachment images for one connection. Downloading and decoding
/// happen off the main thread, a few at a time, so a screen full of photos never
/// blocks the interface. The cache lives in memory only and goes with the connection.
@MainActor
public final class AttachmentLoader {
    let client: HubClient
    let cache = NSCache<NSString, UIImage>()
    /// Original files held in memory only, so a photo opened twice downloads once.
    let originals = NSCache<NSString, NSData>()
    private var noPhoto: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let gate = Gate(limit: 4)

    init(client: HubClient) {
        self.client = client
        cache.totalCostLimit = 96 * 1024 * 1024
        originals.totalCostLimit = 256 * 1024 * 1024
    }

    /// The picture already in memory, so a view can draw it on its very first frame instead of a placeholder.
    func cachedImage(_ id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    /// The contact's picture already in memory.
    func cachedContactPhoto(_ handle: String) -> UIImage? {
        cache.object(forKey: ("contact:" + handle) as NSString)
    }

    func image(_ id: String) async -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        if let running = inFlight[id] { return await running.value }
        let task = Task.detached(priority: .userInitiated) { [client, gate] () -> UIImage? in
            await gate.enter()
            let image: UIImage?
            if let data = try? await client.attachment(id, thumbnail: true) { image = Self.decode(data, maxPixel: 1000) } else { image = nil }
            await gate.leave()
            return image
        }
        inFlight[id] = task
        let image = await task.value
        inFlight[id] = nil
        if let image { cache.setObject(image, forKey: id as NSString, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }

    /// A contact's picture, or nil when they have none. The answer is remembered either way.
    func contactPhoto(_ handle: String) async -> UIImage? {
        let key = "contact:" + handle
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if noPhoto.contains(handle) { return nil }
        let data = try? await client.contactPhoto(handle: handle)
        let image = await Task.detached { data.flatMap { Self.decode($0, maxPixel: 200) } }.value
        if let image { cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4)) } else { noPhoto.insert(handle) }
        return image
    }

    func stream(_ id: String) -> (url: URL, headers: [String: String])? {
        client.attachmentStream(id)
    }

    /// Decodes at reduced size and forces the work now, not later on the main thread at draw time.
    nonisolated static func decode(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Lets only `limit` downloads and decodes run at once.
private actor Gate {
    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { free = limit }

    func enter() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty { free += 1 } else { waiting.removeFirst().resume() }
    }
}
