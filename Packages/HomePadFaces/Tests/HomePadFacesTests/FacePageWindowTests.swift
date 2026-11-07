import Foundation
import Testing
@testable import HomePadFaces

@Suite struct FacePageWindowTests {
    private let faces = (0..<4).map { _ in UUID() }

    @Test func theFacesGoRoundAtBothEnds() {
        let last = FacePageWindow(around: faces[3], order: faces)
        #expect(last.pages.map(\.faceID) == [faces[1], faces[2], faces[3], faces[0], faces[1]])
        let first = FacePageWindow(around: faces[0], order: faces)
        #expect(first.pages.map(\.faceID) == [faces[2], faces[3], faces[0], faces[1], faces[2]])
    }

    /// The page landed on and the ones on either side that stay keep their
    /// identity, so their faces keep running. Only the page beyond is new.
    @Test func movingAlongKeepsThePagesOnScreen() {
        let window = FacePageWindow(around: faces[3], order: faces)
        let landed = window.pages[3]
        let moved = window.centered(on: landed, order: faces)
        #expect(moved.pages.map(\.faceID) == [faces[2], faces[3], faces[0], faces[1], faces[2]])
        #expect(moved.resting == landed)
        #expect(moved.pages[0] == window.pages[1])
        #expect(moved.pages[1] == window.resting)
        #expect(moved.pages[3] == window.pages[4])
        #expect(!window.pages.contains(moved.pages[4]))
    }

    /// A quick second flick lands two pages out, before the window moves along.
    @Test func thereIsAFaceTwoPagesOutOnBothSides() {
        let window = FacePageWindow(around: faces[0], order: faces)
        #expect(window.pages.count == 2 * FacePageWindow.reach + 1)
        #expect(window.pages.first?.faceID == faces[2] && window.pages.last?.faceID == faces[2])
    }

    /// With two faces they alternate, each page its own.
    @Test func twoFacesAlternate() {
        let two = Array(faces.prefix(2))
        let window = FacePageWindow(around: two[0], order: two)
        #expect(window.pages.map(\.faceID) == [two[0], two[1], two[0], two[1], two[0]])
        #expect(Set(window.pages.map(\.id)).count == window.pages.count)
        let back = window.centered(on: window.pages[1], order: two)
        #expect(back.pages.map(\.faceID) == [two[1], two[0], two[1], two[0], two[1]])
        #expect(back.pages[3] == window.resting)
    }

    @Test func oneFaceDoesNotPage() {
        #expect(FacePageWindow(around: faces[0], order: [faces[0]]).pages.count == 1)
    }
}
