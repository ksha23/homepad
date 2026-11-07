import SwiftUI

/// Shows an MJPEG stream with `MJPEGStream`. Calls `onFailure` when the stream
/// fails before its first frame, so the caller can fall back to stills. Once it
/// has shown a frame it reconnects on its own.
struct MJPEGStreamView: View {
    let request: URLRequest
    var maximumFramesPerSecond: Double = 15
    var onFailure: (() -> Void)?
    @State private var stream: MJPEGStream?
    @Environment(\.cameraContentMode) private var contentMode

    var body: some View {
        ZStack {
            if let image = stream?.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                CameraPlaceholder(message: stream?.errorMessage, isLoading: stream?.errorMessage == nil)
            }
        }
        .onAppear {
            // An unstopped stream keeps downloading, since its URLSession holds it.
            self.stream?.stop()
            let stream = MJPEGStream(maximumFramesPerSecond: maximumFramesPerSecond)
            stream.start(request)
            self.stream = stream
        }
        .onDisappear {
            stream?.stop()
            stream = nil
        }
        .onChange(of: stream?.errorMessage) { _, message in
            if message != nil, stream?.image == nil { onFailure?() }
        }
    }
}
