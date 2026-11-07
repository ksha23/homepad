import HomePadUI
import ImageIO
import SwiftUI

/// A small square photo, decoded once, off the main thread, at the size it is
/// shown. Decoding the whole photo in `body` repeated the work on every redraw:
/// each streamed word of an answer, each keystroke in the chat field.
struct PhotoThumbnail: View {
    let data: Data
    /// Edge length in points.
    let side: CGFloat
    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            } else if !failed {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: side, height: side)
            }
        }
        .task(id: data) {
            let pixels = side * displayScale
            let data = data
            let decoded = await Task.detached(priority: .userInitiated) { Self.decode(data, fillingPixels: pixels) }.value
            image = decoded
            failed = decoded == nil
        }
    }

    /// The photo, upright and scaled down so its shorter side is `pixels` long,
    /// enough to fill the square. Nil when the data is not an image.
    nonisolated static func decode(_ data: Data, fillingPixels pixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        let longest = pixels * CGFloat(max(width, height) / min(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}
