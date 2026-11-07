import CommsKit
import SwiftUI

/// One photo in the viewer, zoomable, with a progress ring while the original loads.
struct PhotoPage: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.displayScale) private var scale
    let attachment: CommsAttachment
    @State private var model = PhotoPageModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = model.shown {
                    ZoomScrollView(image: image)
                }
                if model.isLoading {
                    ProgressRing(value: model.progress)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 40)
                }
                if model.failed {
                    Label("Photo unavailable", systemImage: "photo.badge.exclamationmark").foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: attachment.id) {
                let pixel = AttachmentLoader.viewerPixelSize(screenPoints: proxy.size, scale: scale)
                await model.load(attachment, loader: runtime.store.attachments, maxPixel: pixel)
            }
        }
    }
}

/// A small circular progress indicator for the download.
private struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            if value > 0 && value < 1 {
                ProgressView(value: value).progressViewStyle(.circular)
            } else {
                ProgressView()
            }
        }
        .tint(.white)
        .padding(12)
        .background(.black.opacity(0.45), in: Circle())
        .accessibilityLabel("Loading full resolution photo")
    }
}
