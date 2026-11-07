import CoreGraphics
import Testing
@testable import HomePadSmartHome

@Suite("Camera grid layout")
struct CameraGridLayoutTests {
    private let landscape11 = CGSize(width: 1100, height: 640)

    @Test(arguments: 1...9)
    func tilesKeepTheCameraShapeAndFit(count: Int) {
        let layout = CameraGridLayout.best(count: count, in: landscape11, spacing: 16)
        #expect(abs(layout.tile.width / layout.tile.height - CameraGridLayout.aspectRatio) < 0.001)
        let rows = (count + layout.columns - 1) / layout.columns
        #expect(CGFloat(layout.columns) * layout.tile.width + CGFloat(layout.columns - 1) * 16 <= landscape11.width + 0.5)
        #expect(CGFloat(rows) * layout.tile.height + CGFloat(rows - 1) * 16 <= landscape11.height + 0.5)
    }

    @Test func twoCamerasSitSideBySideInLandscape() {
        #expect(CameraGridLayout.best(count: 2, in: landscape11, spacing: 16).columns == 2)
    }

    @Test func twoCamerasStackInPortrait() {
        #expect(CameraGridLayout.best(count: 2, in: CGSize(width: 760, height: 1050), spacing: 16).columns == 1)
    }
}
