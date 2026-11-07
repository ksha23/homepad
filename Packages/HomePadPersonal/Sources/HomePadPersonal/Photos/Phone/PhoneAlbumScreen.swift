import HomePadCore
import HomePadUI
import SwiftUI

/// One album of the recognized person's phone, laid out like an album of the
/// iPad's own library: the same grid, the same viewer growing out of its
/// thumbnail, and Play Slideshow. The photos come from the phone, through the
/// iPad's encrypted copy of what it already sent.
///
/// The Photos app draws it only while the phone's library shows, so it goes
/// away, viewer and all, the moment the person stops being recognized.
struct PhoneAlbumScreen: View {
    @Environment(AppServices.self) private var services
    let album: PhoneAlbum
    let deviceName: String
    let onClose: () -> Void

    /// Nil while the phone lists them.
    @State private var photos: [PhotoRef]?
    @State private var viewer: PhotoViewerRequest?
    @State private var viewedPhoto: PhotoRef?
    @State private var thumbnails = ThumbnailFrames()

    var body: some View {
        ZStack {
            AppScreen(album.title, onBack: onClose, backLabel: "Albums", accessory: { playButton }) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Label("\(PhotoAlbum.countText(photos?.count ?? album.count)) on \(deviceName)", systemImage: "iphone")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let photos {
                        PhotoGridView(photos: photos, viewedPhoto: viewedPhoto, hidesViewedPhoto: viewer?.mode == .browse,
                                      thumbnails: thumbnails) { start in
                            viewer = PhotoViewerRequest(photos: photos, start: start, title: album.title, mode: .browse)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .accessibilityHidden(viewer != nil)
            if let viewer {
                PhotoViewer(request: viewer, thumbnailFrame: { [thumbnails] in thumbnails.frame(of: $0) },
                            onShow: { viewedPhoto = $0 }, onClose: closeViewer)
                    .id(viewer.id)
                    .zIndex(1)
            }
        }
        .task(id: album.id) {
            let listed = await services.phonePhotos.photos(in: album)
            guard !Task.isCancelled else { return }
            photos = listed.map(PhotoRef.phone)
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if photos?.isEmpty != true {
            GlassIconButton("play.fill", label: "Play Slideshow", isProminent: true) {
                guard let photos, !photos.isEmpty else { return }
                viewer = PhotoViewerRequest(photos: photos, start: nil, title: album.title, mode: .slideshow)
            }
            .disabled(photos == nil)
        }
    }

    /// Removes the viewer at once, as the iPad's own albums do: it has already
    /// shrunk into its thumbnail or slid away.
    private func closeViewer() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            viewer = nil
            viewedPhoto = nil
        }
    }
}
