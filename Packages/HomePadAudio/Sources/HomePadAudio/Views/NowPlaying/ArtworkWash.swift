import CoreImage
import UIKit

/// The blurred wash of a cover behind Now Playing, made once per cover: the image
/// is shrunk to a few dozen pixels and blurred there, so the screen draws a still
/// picture instead of an 80 point live blur, and the next track's wash is ready
/// before a skip (`prepare`).
@MainActor
enum ArtworkWash {
    private static var cache: [URL: UIImage] = [:]
    private static var order: [URL] = []
    private static var inFlight: [URL: Task<UIImage?, Never>] = [:]

    /// The web image behind a cover address. Apple Music covers use `musicKit://`
    /// addresses that carry the catalog image's web address (`aat` or `fat`).
    /// Nil when there is no web image, such as a generated cover.
    static func webURL(for url: URL?) -> URL? {
        guard let url else { return nil }
        if ["http", "https"].contains(url.scheme) { return url }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["aat", "fat"] {
            if let value = items.first(where: { $0.name == name })?.value, let web = URL(string: value),
               ["http", "https"].contains(web.scheme) {
                return web
            }
        }
        return nil
    }

    /// The wash for a cover, loaded and blurred the first time. Nil when the
    /// cover has no web image or it failed to load.
    static func image(for cover: URL) async -> UIImage? {
        guard let url = webURL(for: cover) else { return nil }
        if let cached = cache[url] { return cached }
        if let existing = inFlight[url] { return await existing.value }
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            let image = await Task.detached(priority: .userInitiated) { blurred(data) }.value
            if let image { store(image, for: url) }
            return image
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        return result
    }

    /// The wash for a web image when it is made already, without waiting.
    static func cachedImage(for url: URL) -> UIImage? {
        cache[url]
    }

    /// Makes the wash ahead of time, for the current or next track.
    static func prepare(_ cover: URL) {
        guard let url = webURL(for: cover), cache[url] == nil, inFlight[url] == nil else { return }
        Task { _ = await image(for: url) }
    }

    /// A few recent covers are enough: the current one, the next and the last.
    private static func store(_ image: UIImage, for url: URL) {
        cache[url] = image
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > 6 { cache[order.removeFirst()] = nil }
    }

    /// One Core Image context for every wash. A context is costly to make, and
    /// one was made for each cover, about every three minutes all day.
    private nonisolated static let context = CIContext()

    private nonisolated static func blurred(_ data: Data) -> UIImage? {
        guard let source = UIImage(data: data) else { return nil }
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let input = CIImage(image: small) else { return small }
        // About an 80 point blur once the 64 pixels are stretched across the screen.
        let soft = input.clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: input.extent)
        guard let output = context.createCGImage(soft, from: input.extent) else { return small }
        return UIImage(cgImage: output)
    }
}
