import CoreImage
import CoreVideo
import Foundation

/// Converts camera frames to JPEG and CGImage, downscaled for the job at hand.
/// Safe to call from any thread (CIContext is thread-safe).
enum FrameEncoder {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// JPEG data no larger than `maxDimension` on its long side.
    static func jpeg(from pixelBuffer: CVPixelBuffer, maxDimension: CGFloat, quality: CGFloat = 0.75) -> Data? {
        let image = scaled(CIImage(cvPixelBuffer: pixelBuffer), maxDimension: maxDimension)
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        return context.jpegRepresentation(of: image, colorSpace: sRGB, options: options)
    }

    /// A CGImage no larger than `maxDimension` on its long side.
    static func cgImage(from pixelBuffer: CVPixelBuffer, maxDimension: CGFloat) -> CGImage? {
        let image = scaled(CIImage(cvPixelBuffer: pixelBuffer), maxDimension: maxDimension)
        return context.createCGImage(image, from: image.extent)
    }

    /// JPEG data for a CGImage (photos picked from the library).
    static func jpeg(from cgImage: CGImage, maxDimension: CGFloat, quality: CGFloat = 0.8) -> Data? {
        let image = scaled(CIImage(cgImage: cgImage), maxDimension: maxDimension)
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        return context.jpegRepresentation(of: image, colorSpace: sRGB, options: options)
    }

    private static func scaled(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > maxDimension, longSide > 0 else { return image }
        let scale = maxDimension / longSide
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
