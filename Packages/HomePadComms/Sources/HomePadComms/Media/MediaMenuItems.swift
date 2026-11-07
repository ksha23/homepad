import CommsKit
import SwiftUI

/// Save to Photos, Save to Files and Send to..., for the download button, the long-press
/// menu and the viewer.
struct MediaMenuItems: View {
    @Environment(CommsRuntime.self) private var runtime
    let attachments: [CommsAttachment]
    let saver: MediaSaver
    let onSend: () -> Void

    var body: some View {
        Button("Save to Photos", systemImage: "photo.badge.arrow.down") {
            Task { await saver.saveToPhotos(attachments, loader: runtime.store.attachments) }
        }
        Button("Save to Files", systemImage: "folder") {
            Task { await saver.saveToFiles(attachments, loader: runtime.store.attachments) }
        }
        Button("Send to...", systemImage: "arrowshape.turn.up.right", action: onSend)
    }
}
