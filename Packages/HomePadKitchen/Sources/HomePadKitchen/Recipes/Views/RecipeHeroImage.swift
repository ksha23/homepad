import HomePadUI
import SwiftUI

/// A recipe's photo: the one picked on this device, else the web image, else a
/// warm gradient with a utensil symbol so every card still looks finished.
/// `RecipePhotoLoader` loads each photo once at the size it is shown.
struct RecipeHeroImage: View {
    let recipe: Recipe
    let library: RecipeLibrary

    @Environment(\.displayScale) private var displayScale
    @State private var longestSide: CGFloat = 0
    /// The last photo loaded, kept on screen while a new size loads.
    @State private var loaded: UIImage?
    @State private var loadedURL: URL?

    private var loader: RecipePhotoLoader { .shared }

    /// The photo fills whatever frame it gets without growing it. A filled photo
    /// laid out directly takes its own aspect ratio, which pushed the title and
    /// facts on a tile outside the clip.
    var body: some View {
        let keys = keys
        Color.clear
            .onGeometryChange(for: CGFloat.self) { max($0.size.width, $0.size.height) } action: { longestSide = $0 }
            .overlay { photo(keys) }
            .clipped()
            .accessibilityHidden(true)
            .task(id: keys) { await load(keys) }
    }

    /// The picked photo first, then the web photo, at the size shown. Empty
    /// until the view has a size.
    private var keys: [RecipePhotoLoader.Key] {
        guard longestSide > 0 else { return [] }
        return [library.localImageURL(for: recipe), recipe.imageURL].compactMap { url in
            url.map { loader.key(for: $0, points: longestSide, scale: displayScale) }
        }
    }

    @ViewBuilder
    private func photo(_ keys: [RecipePhotoLoader.Key]) -> some View {
        if let image = keys.lazy.compactMap(loader.cached).first ?? shownLoaded(keys) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else {
            placeholder
        }
    }

    /// The last loaded photo, while it is still one of this recipe's photos.
    private func shownLoaded(_ keys: [RecipePhotoLoader.Key]) -> UIImage? {
        guard let loadedURL, keys.contains(where: { $0.url == loadedURL }) else { return nil }
        return loaded
    }

    /// Loads the first photo that can be read, in order, unless it is decoded already.
    private func load(_ keys: [RecipePhotoLoader.Key]) async {
        for key in keys {
            if loader.cached(key) != nil { return }
            guard let image = await loader.photo(key) else { continue }
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.standard) {
                loaded = image
                loadedURL = key.url
            }
            return
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [.orange.opacity(0.85), .red.opacity(0.55), .black],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
            }
    }
}
