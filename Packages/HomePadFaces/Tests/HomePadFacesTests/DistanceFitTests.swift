import CoreGraphics
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// A part drawn at its far size and shrunk into its near frame keeps its
/// shape and never grows past its far size.
@Suite struct DistanceFitTests {
    @Test func fittingShrinksButNeverEnlarges() {
        #expect(DistanceFit.scale(CGSize(width: 200, height: 100), into: CGSize(width: 100, height: 100)) == 0.5)
        #expect(DistanceFit.scale(CGSize(width: 200, height: 100), into: CGSize(width: 1000, height: 1000)) == 1)
        #expect(DistanceFit.scale(.zero, into: CGSize(width: 10, height: 10)) == 1)
    }

    @Test func fittedFramesKeepTheirShapeAndAnchor() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 100)
        let leading = DistanceFit.fitted(CGSize(width: 200, height: 100), in: rect, anchor: .leading)
        #expect(leading == CGRect(x: 10, y: 45, width: 100, height: 50))
        let center = DistanceFit.fitted(CGSize(width: 200, height: 100), in: rect)
        #expect(center == CGRect(x: 10, y: 45, width: 100, height: 50))
        let topLeading = DistanceFit.fitted(CGSize(width: 100, height: 200), in: rect, anchor: .topLeading)
        #expect(topLeading == CGRect(x: 10, y: 20, width: 50, height: 100))
    }

    @Test func detailFadesInOnceTheBigFactHasMadeRoom() {
        #expect(ProximityDetailTransition.opacity(at: 0) == 0)
        #expect(ProximityDetailTransition.opacity(at: 0.6) == 0)
        #expect(abs(ProximityDetailTransition.opacity(at: 0.8) - 0.5) < 0.0001)
        #expect(ProximityDetailTransition.opacity(at: 1) == 1)
        #expect(ProximityDetailTransition.opacity(at: 1.05) == 1, "a spring's overshoot stays opaque")
    }
}
