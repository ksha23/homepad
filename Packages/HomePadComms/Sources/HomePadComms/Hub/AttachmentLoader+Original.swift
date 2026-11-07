import Foundation
import UIKit

extension AttachmentLoader {
    /// The original file of an attachment. A copy is kept in memory (never on disk),
    /// so opening, saving and forwarding the same photo download it once.
    func original(_ id: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Data {
        if let cached = originals.object(forKey: id as NSString) { return cached as Data }
        let data = try await client.downloadOriginal(id, progress: progress)
        originals.setObject(data as NSData, forKey: id as NSString, cost: data.count)
        return data
    }

    /// A screen-sized image from original bytes. The decode runs off the main thread and
    /// never makes the full-resolution bitmap, only one sized for the display.
    func screenImage(from data: Data, maxPixel: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { Self.decode(data, maxPixel: maxPixel) }.value
    }

    /// The longest side to decode for the current screen, with room to zoom, capped to bound memory.
    nonisolated static func viewerPixelSize(screenPoints: CGSize, scale: CGFloat) -> Int {
        let longest = max(screenPoints.width, screenPoints.height) * scale
        return Int(min(max(longest * 2, 1024), 3072))
    }
}
