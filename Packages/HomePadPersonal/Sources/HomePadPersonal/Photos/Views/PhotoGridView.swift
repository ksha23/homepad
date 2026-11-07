import HomePadCore
import HomePadUI
import SwiftUI

/// The photos and videos of one album as square thumbnails, as many columns
/// as fit, videos badged with their length. Tapping one opens it full screen.
///
/// While the viewer is open the grid follows it: it scrolls to the photo on
/// screen, so closing lands on it, and hides that photo's thumbnail, which the
/// viewer's photo shrinks back into.
struct PhotoGridView: View {
    let photos: [PhotoRef]
    /// The photo the viewer shows, kept in view.
    var viewedPhoto: PhotoRef?
    /// True while the viewer's photo stands in for its thumbnail.
    var hidesViewedPhoto = false
    /// Where each thumbnail sits, for the viewer.
    var thumbnails: ThumbnailFrames?
    /// The photo at the top, saved when scrolling stops and scrolled back to
    /// when the album opens again.
    var topPhotoID: Binding<String?> = .constant(nil)
    let onOpen: (PhotoRef) -> Void
    @Environment(PhotoLibraryService.self) private var library

    var body: some View {
        if photos.isEmpty {
            EmptyStateView("No Photos", message: "This album has no photos HomePad can show.", systemImage: "photo")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: PhotoGridMetrics.minimumThumbnail), spacing: PhotoGridMetrics.spacing)],
                              spacing: PhotoGridMetrics.spacing) {
                        ForEach(photos) { photo in
                            thumbnail(photo)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .scrollIndicators(.hidden)
                .restoresScrollPosition(topPhotoID)
                .onChange(of: viewedPhoto) { _, photo in
                    guard let photo else { return }
                    // Out of sight behind the viewer, so no animation.
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { proxy.scrollTo(photo.id) }
                }
            }
        }
    }

    private func thumbnail(_ photo: PhotoRef) -> some View {
        let duration = library.videoDuration(for: photo)
        return Button { onOpen(photo) } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { PhotoView(photo: photo, targetSize: PhotoGridMetrics.thumbnailPixels) }
                .overlay(alignment: .bottomTrailing) {
                    if let duration { VideoDurationBadge(duration: duration) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hidesViewedPhoto && photo == viewedPhoto ? 0 : 1)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            thumbnails?.set(frame, for: photo)
        }
        .onDisappear { thumbnails?.remove(photo) }
        .accessibilityLabel(duration == nil ? "Photo" : "Video")
        .accessibilityIdentifier("photos.grid.\(photo.id)")
    }
}
