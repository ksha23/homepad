import CoreImage
import ImageIO
import HomePadCore
import HomePadUI
import SwiftUI

/// One photo filling exactly the frame it is offered: a library photo loaded
/// through PhotoKit, or demo art. Shared by the Photos app, the slideshow and
/// the Photo widget.
///
/// The placeholder takes the offered size and the photo is drawn over it, so
/// a wide or tall photo is cropped to the frame instead of widening it into
/// its neighbors.
struct PhotoView: View {
    @Environment(PhotoLibraryService.self) private var photos
    @Environment(AppServices.self) private var services
    let photo: PhotoRef
    /// Pixel size to request. Grids ask for small images, the slideshow for screen size.
    var targetSize = CGSize(width: 600, height: 600)
    /// `.fit` shows the whole photo over a soft, dimmed copy of itself, for the slideshow.
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var backdrop: UIImage?

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.06))
            .overlay { softBackdrop }
            .overlay { picture }
            .clipped()
            .task(id: photo) {
                switch photo {
                case .library(let id):
                    show(await photos.image(for: id, targetSize: targetSize))
                case .phone(let phonePhoto):
                    await loadFromPhone(phonePhoto)
                case .demo:
                    break
                }
            }
    }

    /// Each layer is its own overlay, so each is offered exactly the frame.
    /// In one ZStack the filled backdrop would widen the stack and stretch
    /// the fitted photo with it.
    @ViewBuilder
    private var softBackdrop: some View {
        if let backdrop {
            Image(uiImage: backdrop)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.35))
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var picture: some View {
        switch photo {
        case .demo(let index):
            DemoPhotoArt(index: index)
        case .library, .phone:
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
    }

    private func show(_ loaded: UIImage?) {
        let soft = contentMode == .fit ? loaded.flatMap(Self.softened) : nil
        withAnimation(Theme.Motion.standard) {
            image = loaded
            backdrop = soft
        }
    }

    /// The thumbnail first, then the full image only for a frame bigger than
    /// any grid or cover, as the viewer and the slideshow are. Covers asked for
    /// the full 2048 point image each, which pulled it over the network and
    /// drew a 12 MB bitmap into a small cover, and the Photos menu stuttered.
    private func loadFromPhone(_ phonePhoto: PhonePhoto) async {
        let longest = max(targetSize.width, targetSize.height)
        if let data = await services.phonePhotos.thumbnail(of: phonePhoto.id) {
            show(await Self.decoded(data, longestSide: longest))
        }
        guard longest > Self.largestGridPixels, !Task.isCancelled,
              let data = await services.phonePhotos.fullImage(of: phonePhoto.id),
              let full = await Self.decoded(data, longestSide: longest), !Task.isCancelled else { return }
        show(full)
    }

    /// The largest size a grid cell or an album cover asks for. Anything bigger is a full-screen view.
    private static let largestGridPixels = max(PhotoGridMetrics.coverPixels.width, PhotoGridMetrics.coverPixels.height)

    /// Decodes off the main thread, so a full image never stalls a page turn, and no larger than the
    /// frame asks for (`longestSide` pixels), as PhotoKit hands library photos over at the size asked.
    private static func decoded(_ data: Data, longestSide: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(longestSide.rounded(.up))),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    /// A small blurred copy, blurred once here rather than by a live filter
    /// that would redraw on every frame of the slideshow's slow zoom.
    private static func softened(_ image: UIImage) -> UIImage? {
        let width: CGFloat = 160
        let size = CGSize(width: width, height: max(1, width * image.size.height / max(image.size.width, 1)))
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let input = CIImage(image: small) else { return nil }
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: input.extent)
        guard let output = blurContext.createCGImage(blurred, from: input.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    /// One Core Image context for every slide. Making a context is costly (it
    /// sets up a GPU pipeline), and the slideshow blurred a new photo every few
    /// seconds for as long as it ran.
    private static let blurContext = CIContext()
}
