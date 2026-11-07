import Foundation
import HomePadCore
import HomePadUI
import Observation
import UIKit

/// Keeps one wallpaper photo per member on disk (Application Support), scaled
/// down to screen size so it stays light in memory.
@MainActor
@Observable
final class WallpaperPhotoStore {
    /// Bumped on every save so views reload the image.
    private(set) var revision = 0
    /// Each photo's tone from its average color, for the glass widgets over
    /// it, by member. Measured once a photo loads (`measureTone(for:)`).
    private var tones: [String: BackdropTone] = [:]
    @ObservationIgnored private var measuring: Set<String> = []
    @ObservationIgnored private var cache: [String: UIImage] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let log = Log.make("Wallpaper")

    init(directory: URL? = nil) {
        self.directory = directory ?? Files.standard.directory
    }

    /// The member's photo, if one was saved.
    func image(for memberID: HouseholdMember.ID?) -> UIImage? {
        _ = revision
        let key = Self.key(memberID)
        if let cached = cache[key] { return cached }
        guard let image = UIImage(contentsOfFile: url(for: key).path) else { return nil }
        cache[key] = image
        return image
    }

    /// How bright the member's photo is, or nil until it has been measured.
    func tone(for memberID: HouseholdMember.ID?) -> BackdropTone? {
        tones[Self.key(memberID)]
    }

    /// Measures the member's photo when its tone is not known yet: its average
    /// color, from a small copy drawn off the main thread.
    func measureTone(for memberID: HouseholdMember.ID?) async {
        let key = Self.key(memberID)
        guard tones[key] == nil, !measuring.contains(key), let image = image(for: memberID)?.cgImage else { return }
        measuring.insert(key)
        defer { measuring.remove(key) }
        let started = revision
        let tone = await Task.detached(priority: .utility) { Self.averageTone(of: image) }.value
        // A photo saved meanwhile is measured next time.
        guard revision == started, let tone else { return }
        tones[key] = tone
    }

    /// The tone of an image's average color: it is drawn into a 32 by 32
    /// bitmap and the pixels averaged.
    nonisolated static func averageTone(of image: CGImage) -> BackdropTone? {
        let side = 32
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var sums = (red: 0.0, green: 0.0, blue: 0.0)
        for pixel in 0..<(side * side) {
            sums.red += Double(bytes[pixel * 4])
            sums.green += Double(bytes[pixel * 4 + 1])
            sums.blue += Double(bytes[pixel * 4 + 2])
        }
        let count = Double(side * side) * 255
        return BackdropTone(red: sums.red / count, green: sums.green / count, blue: sums.blue / count)
    }

    /// Saves picked image data, downscaled to at most 2732 points on the long side.
    /// Returns false when the data is not an image.
    @discardableResult
    func save(_ data: Data, for memberID: HouseholdMember.ID?) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let scaled = image.preparingThumbnail(of: Self.fittingSize(image.size, maxSide: 2732)) ?? image
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let key = Self.key(memberID)
            try jpeg.write(to: url(for: key), options: .atomic)
            cache[key] = scaled
            tones[key] = nil
            revision += 1
            return true
        } catch {
            log.error("Saving wallpaper failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func url(for key: String) -> URL {
        Files(directory: directory).url(for: key)
    }

    nonisolated fileprivate static func key(_ memberID: HouseholdMember.ID?) -> String {
        memberID?.uuidString ?? "guest"
    }

    private static func fittingSize(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

extension WallpaperPhotoStore {
    /// Where the photos live: one JPEG per member, and one for guests, in
    /// Application Support/Wallpapers.
    struct Files: Sendable {
        let directory: URL

        static var standard: Files {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return Files(directory: base.appendingPathComponent("Wallpapers", isDirectory: true))
        }

        func url(for key: String) -> URL {
            directory.appendingPathComponent("\(key).jpg")
        }

        /// Gives a person's photo their new ID. A photo already under the new ID is replaced.
        func move(from old: UUID, to new: UUID) {
            let source = url(for: WallpaperPhotoStore.key(old))
            let target = url(for: WallpaperPhotoStore.key(new))
            let files = FileManager.default
            guard files.fileExists(atPath: source.path) else { return }
            if files.fileExists(atPath: target.path) {
                _ = try? files.replaceItemAt(target, withItemAt: source)
            } else {
                try? files.moveItem(at: source, to: target)
            }
        }
    }
}
