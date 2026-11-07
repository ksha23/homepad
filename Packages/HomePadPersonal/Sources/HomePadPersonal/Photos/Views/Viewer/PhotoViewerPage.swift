import HomePadUI
import SwiftUI

/// One page of the full-screen viewer: a photo, or a video with the system's
/// playback controls over its first frame.
///
/// The photo fills `photoRect`, which the viewer moves: browsing, it is the
/// photo fitted to the screen at rest and its thumbnail's square while the
/// viewer opens and closes, so the photo grows out of the grid and shrinks back
/// into it with its crop changing as it goes. A slideshow's `photoRect` is the
/// whole page, where each photo shows whole over a soft copy of itself. Pulled
/// down, either one is smaller and lower.
struct PhotoViewerPage: View {
    let photo: PhotoRef
    let mode: PhotoViewerRequest.Mode
    /// Where the photo sits in the page.
    let photoRect: CGRect
    let cornerRadius: CGFloat
    /// The page on screen. Only it plays a video.
    let isActive: Bool
    /// False while the viewer opens or closes, when a video shows its first frame.
    let showsVideo: Bool
    /// The slideshow's slow zoom.
    var zoom: CGFloat = 1
    var onVideoFinished: () -> Void = {}

    @Environment(PhotoLibraryService.self) private var library

    /// Large enough for a 13-inch iPad's long side.
    static let targetSize = CGSize(width: 2400, height: 2400)

    var body: some View {
        ZStack {
            switch mode {
            case .browse:
                PhotoView(photo: photo, targetSize: Self.targetSize, contentMode: .fill)
                    .frame(width: max(1, photoRect.width), height: max(1, photoRect.height))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .position(x: photoRect.midX, y: photoRect.midY)
            case .slideshow:
                PhotoView(photo: photo, targetSize: Self.targetSize, contentMode: .fit)
                    .scaleEffect(zoom)
                    .frame(width: max(1, photoRect.width), height: max(1, photoRect.height))
                    .position(x: photoRect.midX, y: photoRect.midY)
            }
            if showsVideo, case .library(let id) = photo, library.videoDuration(for: photo) != nil {
                // Over its first frame, at the same size, so the system's
                // controls sit on the video and clear of the viewer's header.
                let video = videoRect
                PhotoVideoPlayer(id: id, isActive: isActive, onFinished: onVideoFinished)
                    .frame(width: max(1, video.width), height: max(1, video.height))
                    .position(x: video.midX, y: video.midY)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: library.videoDuration(for: photo) == nil ? .ignore : .contain)
        .accessibilityLabel(library.videoDuration(for: photo) == nil ? "Photo" : "Video")
        .accessibilityAddTraits(.isImage)
    }

    /// The video at its own shape inside `photoRect`, which is already that
    /// shape when browsing.
    private var videoRect: CGRect {
        PhotoPaging.fittedRect(aspectRatio: library.aspectRatio(for: photo), in: photoRect.size)
            .offsetBy(dx: photoRect.minX, dy: photoRect.minY)
    }
}
