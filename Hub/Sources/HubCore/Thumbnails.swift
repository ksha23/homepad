import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small JPEG copies of photos, cached on disk. A phone photo is several megabytes, and
/// a thread of them is far too much to send to an iPad over Tailscale.
enum Thumbnails {
    static let cacheDirectory = URL(fileURLWithPath: NSHomeDirectory() + "/.homepad-hub/cache/thumbs", isDirectory: true)

    /// The cached thumbnail for `guid`, made from `file` on first use. Nil if the image cannot be read.
    static func jpeg(for file: URL, guid: String, maxPixel: Int = 900) -> URL? {
        let safe = guid.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard !safe.isEmpty else { return nil }
        let cached = cacheDirectory.appendingPathComponent("\(safe)-\(maxPixel).jpg")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }

        if file.pathExtension.lowercased() == "pdf" { return firstPage(of: file, to: cached, maxPixel: maxPixel) }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let temporary = cacheDirectory.appendingPathComponent("\(safe)-\(maxPixel).tmp")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        try? FileManager.default.moveItem(at: temporary, to: cached)
        return cached
    }

    /// A JPEG of a PDF's first page on white, with its longest side at `maxPixel`.
    private static func firstPage(of file: URL, to cached: URL, maxPixel: Int) -> URL? {
        guard let document = CGPDFDocument(file as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let turn = page.rotationAngle % 180 != 0
        let size = turn ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(maxPixel) / max(size.width, size.height)
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let temporary = cacheDirectory.appendingPathComponent(cached.deletingPathExtension().lastPathComponent + ".tmp")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        try? FileManager.default.moveItem(at: temporary, to: cached)
        return cached
    }
}
