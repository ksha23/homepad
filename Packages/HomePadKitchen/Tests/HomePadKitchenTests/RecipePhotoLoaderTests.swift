import Foundation
import Testing
import UIKit
@testable import HomePadKitchen

/// Recipe photos load once per shown size, and a replaced photo loads again.
@MainActor
@Suite struct RecipePhotoLoaderTests {
    let loader = RecipePhotoLoader()
    let file = FileManager.default.temporaryDirectory.appending(path: "recipe-photo-\(UUID().uuidString).png")

    /// A plain 1200 by 800 picture on disk, like a photo picked for a recipe.
    private func writePhoto(color: UIColor) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format)
            .image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        try #require(image.pngData()).write(to: file)
    }

    @Test func sizesRoundUpToAFewSteps() {
        let url = URL(string: "https://www.themealdb.com/images/media/meals/1.jpg")!
        #expect(loader.key(for: url, points: 168, scale: 2).pixels == 512)
        #expect(loader.key(for: url, points: 100, scale: 2).pixels == 256)
        #expect(loader.key(for: url, points: 1366, scale: 2).pixels == 2732)
        #expect(loader.key(for: url, points: 3000, scale: 3).pixels == 2732)
    }

    @Test func decodesOnceAtTheShownSize() async throws {
        try writePhoto(color: .orange)
        let key = loader.key(for: file, points: 200, scale: 2)
        #expect(loader.cached(key) == nil)
        let image = try #require(await loader.photo(key))
        #expect(max(image.size.width, image.size.height) <= CGFloat(key.pixels))
        #expect(loader.cached(key) === image)
    }

    @Test func aReplacedPhotoLoadsAgain() async throws {
        try writePhoto(color: .orange)
        let first = loader.key(for: file, points: 200, scale: 2)
        _ = await loader.photo(first)
        loader.forget(file)
        let second = loader.key(for: file, points: 200, scale: 2)
        #expect(second != first)
        #expect(loader.cached(second) == nil)
    }

    @Test func aMissingFileLoadsNothing() async {
        let key = loader.key(for: file.appending(path: "missing"), points: 200, scale: 2)
        #expect(await loader.photo(key) == nil)
    }
}
