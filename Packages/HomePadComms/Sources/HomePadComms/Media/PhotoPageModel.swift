import CommsKit
import Observation
import UIKit

/// The state of one page in the viewer: the thumbnail first, then the original with progress.
@MainActor
@Observable
final class PhotoPageModel {
    private(set) var thumbnail: UIImage?
    private(set) var sharp: UIImage?
    private(set) var progress = 0.0
    private(set) var failed = false

    /// What to draw now: the sharp image when it is ready, else the thumbnail.
    var shown: UIImage? { sharp ?? thumbnail }
    var isLoading: Bool { sharp == nil && !failed }

    /// Shows the cached thumbnail, downloads the original, and decodes it off the main
    /// thread at a size that fits the screen with room to zoom.
    func load(_ attachment: CommsAttachment, loader: AttachmentLoader?, maxPixel: Int) async {
        guard let loader else { failed = true; return }
        failed = false
        progress = 0
        thumbnail = await loader.image(attachment.id)
        do {
            let data = try await loader.original(attachment.id) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            if let image = await loader.screenImage(from: data, maxPixel: maxPixel) {
                sharp = image
            } else {
                failed = thumbnail == nil
            }
        } catch is CancellationError {
            return
        } catch {
            failed = thumbnail == nil
        }
    }
}
