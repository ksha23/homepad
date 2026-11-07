import CommsKit
import CoreGraphics

/// The size a photo or PDF page is drawn at in a bubble: as large as fits in `box`, keeping
/// its shape. Known before the picture loads, so the thread's layout never shifts when it arrives.
enum MediaFit {
    /// `fallback` is used when the hub did not say how big the picture is.
    static func size(of attachment: CommsAttachment, in box: CGSize, fallback: CGSize) -> CGSize {
        guard let width = attachment.width, let height = attachment.height, width > 0, height > 0 else { return fallback }
        let scale = min(box.width / CGFloat(width), box.height / CGFloat(height))
        return CGSize(width: (CGFloat(width) * scale).rounded(), height: (CGFloat(height) * scale).rounded())
    }

    static let photoBox = CGSize(width: 320, height: 420)
    static let photoFallback = CGSize(width: 320, height: 240)
    static let pageBox = CGSize(width: 260, height: 340)
}
