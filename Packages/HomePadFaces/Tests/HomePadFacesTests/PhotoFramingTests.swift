import CoreGraphics
import Testing
@testable import HomePadFaces

/// One Photo framing: zoom and position, always covering the screen.
@Suite struct PhotoFramingTests {
    private let screen = CGSize(width: 1200, height: 800)
    private let landscapePhoto = CGSize(width: 4000, height: 3000)
    private let portraitPhoto = CGSize(width: 3000, height: 4000)

    @Test func plainFramingFillsTheScreenCentered() {
        let (size, offset) = PhotoFraming().placement(imageSize: landscapePhoto, viewSize: screen)
        #expect(size.width == 1200)
        #expect(size.height == 900)
        #expect(offset == .zero)
    }

    @Test func plainFramingMapsLikeTheCenteredFill() {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
        let framed = PhotoFraming().imageRect(forViewRect: rect, viewSize: screen, imageSize: portraitPhoto)
        let centered = DepthLayout.imageRect(forViewRect: rect, viewSize: screen, imageSize: portraitPhoto)
        #expect(abs(framed.minX - centered.minX) < 0.0001)
        #expect(abs(framed.minY - centered.minY) < 0.0001)
        #expect(abs(framed.width - centered.width) < 0.0001)
        #expect(abs(framed.height - centered.height) < 0.0001)
    }

    @Test func aPortraitPhotoMovesUpAndDownButNotSideways() {
        let moved = PhotoFraming().moved(by: CGSize(width: 300, height: -200), imageSize: portraitPhoto, viewSize: screen)
        // Filled to 1200 by 1600: no room sideways, 400 points each way up and down.
        #expect(moved.center.x == 0.5)
        #expect(abs(moved.center.y - (0.5 + 200.0 / 1600)) < 0.0001)
    }

    @Test func theScreenNeverShowsPastAnEdge() {
        let pushed = PhotoFraming().moved(by: CGSize(width: 0, height: 5000), imageSize: portraitPhoto, viewSize: screen)
        let (_, offset) = pushed.placement(imageSize: portraitPhoto, viewSize: screen)
        #expect(offset.height == 400)
    }

    @Test func zoomStaysInRange() {
        #expect(PhotoFraming().zoomed(by: 0.2).zoom == 1)
        #expect(PhotoFraming().zoomed(by: 10).zoom == PhotoFraming.maxZoom)
    }

    @Test func framingRoundTripsThroughSavedValues() {
        var values: [String: String] = [:]
        let framing = PhotoFraming(zoom: 2.5, center: CGPoint(x: 0.3, y: 0.7))
        framing.write(to: &values)
        #expect(PhotoFraming(values: values) == framing)
        PhotoFraming.clear(from: &values)
        #expect(PhotoFraming(values: values) == PhotoFraming())
    }
}
