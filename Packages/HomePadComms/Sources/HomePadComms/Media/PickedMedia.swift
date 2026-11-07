import Foundation
import UniformTypeIdentifiers

/// Names and types for photos and videos chosen in the composer.
enum PickedMedia {
    /// `IMG_20261026_101500_1.heic` style name. Videos start with `VID`.
    static func filename(for type: UTType?, index: Int, date: Date = Date()) -> String {
        let isVideo = type?.conforms(to: .movie) ?? false
        let ext = type?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d%02d%02d_%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "\(isVideo ? "VID" : "IMG")_\(stamp)_\(index + 1).\(ext)"
    }

    static func mimeType(for type: UTType?) -> String {
        type?.preferredMIMEType ?? "application/octet-stream"
    }
}
