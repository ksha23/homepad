import CoreGraphics
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Modular from across the room: the date and the clock fill the info panel
/// beside the widgets, and up close each part is the far one shrunk into its
/// top half.
@Suite struct ModularDistanceTests {
    private static let sizes = [CGSize(width: 1210, height: 850), CGSize(width: 850, height: 1210),
                                CGSize(width: 1392, height: 1048), CGSize(width: 1048, height: 1392)]

    @MainActor @Test func acrossTheRoomTheDateAndClockFillTheInfoPanel() throws {
        let support = try #require(FaceCatalog.definition("faces.modular")).widgets
        let base = Theme.Spacing.screenContent
        for size in Self.sizes {
            for hasWidgets in [false, true] {
                let insets = FaceWidgetRoomTests.insets(support, size: size, base: base, hasWidgets: hasWidgets)
                let layout = ModularLayout(size: size, insets: insets)
                let label = "\(size) widgets \(hasWidgets)"
                for isDigital in [false, true] {
                    let far = layout.heroLayout(isDigital: isDigital, isNear: false)
                    let near = layout.heroLayout(isDigital: isDigital, isNear: true)
                    let bounds = layout.info.insetBy(dx: -0.5, dy: -0.5)
                    #expect(bounds.contains(far.date) && bounds.contains(far.clock), "\(label) digital \(isDigital)")
                    #expect(layout.hero.insetBy(dx: -0.5, dy: -0.5).contains(near.date), "\(label) digital \(isDigital)")
                    #expect(layout.hero.insetBy(dx: -0.5, dy: -0.5).contains(near.clock), "\(label) digital \(isDigital)")
                    // Never smaller from afar: up close each part is the far one shrunk.
                    #expect(far.clock.width >= near.clock.width - 0.5, "\(label) digital \(isDigital)")
                    // The time never shrinks. Beside widgets the analog date may, to give the dial room.
                    if isDigital || !hasWidgets {
                        #expect(far.numeral >= near.numeral - 0.5, "\(label) digital \(isDigital)")
                    }
                }
                // The analog dial is the big fact: clearly larger from afar.
                let far = layout.heroLayout(isDigital: false, isNear: false)
                let near = layout.heroLayout(isDigital: false, isNear: true)
                #expect(far.clock.width > near.clock.width * (hasWidgets ? 1.1 : 1.3), "\(label)")
            }
        }
    }

    @Test func aTallFaceStacksTheDateAboveTheDialFromAfar() {
        let layout = ModularLayout(size: CGSize(width: 850, height: 1210))
        let far = layout.heroLayout(isDigital: false, isNear: false)
        #expect(far.date.maxY <= far.clock.minY)
        #expect(far.clock.width > layout.content.width * 0.85)
        let wide = ModularLayout(size: CGSize(width: 1210, height: 850))
        let side = wide.heroLayout(isDigital: false, isNear: false)
        #expect(side.date.maxX <= side.clock.minX, "side by side on a wide face")
    }
}
