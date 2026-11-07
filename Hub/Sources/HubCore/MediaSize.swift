import CoreGraphics
import Foundation
import ImageIO

/// The upright pixel size of a photo, or of a PDF's first page, read from the file's header
/// without decoding it. Remembered per file, since a thread asks for the same ones again.
enum MediaSize {
    private static let cache = NSCache<NSString, NSValue>()

    static func of(_ file: URL, mimeType: String) -> CGSize? {
        let key = file.path as NSString
        if let known = cache.object(forKey: key) { return known.sizeValue }
        let size: CGSize?
        if mimeType == "application/pdf" || file.pathExtension.lowercased() == "pdf" {
            size = pdfPage(file)
        } else if mimeType.hasPrefix("image/") {
            size = image(file)
        } else {
            size = nil
        }
        if let size { cache.setObject(NSValue(size: size), forKey: key) }
        return size
    }

    private static func image(_ file: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // EXIF orientations 5 to 8 are turned a quarter, so the picture shows the other way round.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func pdfPage(_ file: URL) -> CGSize? {
        guard let page = CGPDFDocument(file as CFURL)?.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        return page.rotationAngle % 180 != 0 ? CGSize(width: box.height, height: box.width) : box.size
    }
}
