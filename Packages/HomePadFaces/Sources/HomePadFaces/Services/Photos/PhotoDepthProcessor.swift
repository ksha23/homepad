import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import HomePadCore
import Vision

/// Turns a photo into a `PhotoFrame`: finds the subject with Vision (people,
/// pets or other foreground objects) for HomeView's depth effect, and picks
/// a tint from the photo. Runs off the main thread and caches results in
/// memory and, for subject masks, on disk.
actor PhotoDepthProcessor {
    private let log = Log.make("Faces.Depth")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var cache: [String: PhotoFrame] = [:]
    private var order: [String] = []
    private let memoryLimit = 4
    private let maskCache = MaskDiskCache()

    /// Returns a processed frame, from cache when possible. `load` supplies the
    /// image and, for demo scenes, a ready-made mask.
    func frame(for ref: PhotoRef, maxPixel: Int,
               load: @Sendable () async -> (image: CGImage, mask: CGImage?)?) async -> PhotoFrame? {
        let key = "\(ref.id)@\(maxPixel)"
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        guard let loaded = await load() else { return nil }
        let rawMask = loaded.mask ?? cachedOrVisionMask(for: ref, image: loaded.image)
        let mask = rawMask.flatMap { alphaMask(from: $0, size: CGSize(width: loaded.image.width, height: loaded.image.height)) }
        let sample = rawMask.flatMap { Self.sample($0) }
        let frame = PhotoFrame(ref: ref, image: loaded.image, mask: mask, sample: sample, tint: averageTint(of: loaded.image))
        store(frame, key: key)
        return frame
    }

    // MARK: Subject mask

    private func cachedOrVisionMask(for ref: PhotoRef, image: CGImage) -> CGImage? {
        if let cached = maskCache.mask(for: ref.id) { return cached }
        guard let mask = visionMask(for: image) else { return nil }
        maskCache.store(mask, for: ref.id)
        return mask
    }

    /// A grayscale subject mask: foreground instances first (people, pets,
    /// objects), then person segmentation when that finds nothing or fails.
    private func visionMask(for image: CGImage) -> CGImage? {
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            if let observation = request.results?.first, !observation.allInstances.isEmpty {
                let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                if let mask = grayscaleImage(from: buffer) { return mask }
            }
        } catch {
            log.info("Foreground mask unavailable: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try handler.perform([request])
            if let buffer = request.results?.first?.pixelBuffer {
                return grayscaleImage(from: buffer)
            }
        } catch {
            log.info("Person segmentation unavailable: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func grayscaleImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return context.createCGImage(image, from: image.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    /// Feathers a grayscale mask and turns it into a white image whose alpha
    /// is the mask, scaled to the photo, ready for SwiftUI's `.mask`.
    private func alphaMask(from mask: CGImage, size: CGSize) -> CGImage? {
        let input = CIImage(cgImage: mask)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: size.width / input.extent.width,
                                                             y: size.height / input.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = scaled.clampedToExtent()
        blur.radius = Float(max(size.width, size.height) / 900)
        let toAlpha = CIFilter.maskToAlpha()
        toAlpha.inputImage = blur.outputImage?.cropped(to: CGRect(origin: .zero, size: size))
        guard let output = toAlpha.outputImage else { return nil }
        return context.createCGImage(output, from: CGRect(origin: .zero, size: size), format: .RGBA8,
                                     colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Downsamples a mask to 64 by 64 for coverage checks.
    static func sample(_ mask: CGImage, side: Int = 64) -> MaskSample? {
        var values = [UInt8](repeating: 0, count: side * side)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(mask, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? MaskSample(width: side, height: side, values: values) : nil
    }

    // MARK: Tint

    private func averageTint(of image: CGImage) -> PhotoTint {
        let input = CIImage(cgImage: image)
        let average = CIFilter.areaAverage()
        average.inputImage = input
        average.extent = input.extent
        guard let output = average.outputImage else { return .white }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return PhotoTint(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    // MARK: Memory cache

    private func store(_ frame: PhotoFrame, key: String) {
        cache[key] = frame
        touch(key)
        while order.count > memoryLimit {
            cache[order.removeFirst()] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
