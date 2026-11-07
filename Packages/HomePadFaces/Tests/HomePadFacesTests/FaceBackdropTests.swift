import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Behind the Home Screen (`\.isFrosted`) a face draws only its picture or
/// background. These faces have a still background, so drawn there at two
/// different times they look exactly the same: no time, date, text or tiles.
/// Drawn on the wall, the same two times look different, which shows the
/// times reach the face.
@MainActor
@Suite struct FaceBackdropTests {
    enum Face: String, CaseIterable {
        case modularAnalog, modularDigital, home, homeControls, calendarMonth, calendarUpNext
        case analogEmbossed, analogPrecision, numerals, digital, worldClock, night

        var id: String {
            switch self {
            case .modularAnalog, .modularDigital: "faces.modular"
            case .home, .homeControls: "faces.homeModular"
            case .calendarMonth, .calendarUpNext: "faces.calendar"
            case .analogEmbossed, .analogPrecision: "faces.analog"
            case .numerals: "faces.numerals"
            case .digital: "faces.digital"
            case .worldClock: "faces.worldclock"
            case .night: "faces.night"
            }
        }

        var style: String? {
            switch self {
            case .modularAnalog: "analog"
            case .modularDigital: "digital"
            case .home: "classic"
            case .homeControls: "controls"
            case .calendarMonth: "month"
            case .calendarUpNext: "upNext"
            case .analogEmbossed: "embossed"
            case .analogPrecision: "precision"
            case .numerals, .digital, .worldClock, .night: nil
            }
        }

        /// Whether the face on the wall shows the time, so two times differ.
        var showsTimeOnTheWall: Bool {
            self != .homeControls
        }
    }

    /// A day, three hours and seventeen minutes apart: another date, hour and minute.
    static let later: TimeInterval = 86_400 + 3 * 3600 + 17 * 60

    @Test(arguments: Face.allCases)
    func frostedFaceShowsNoTimeOrText(_ face: Face) throws {
        let now = try #require(render(face, isFrosted: true, offset: 0))
        let later = try #require(render(face, isFrosted: true, offset: Self.later))
        #expect(now == later, "behind the Home Screen \(face) changed with the time")
    }

    @Test(arguments: Face.allCases.filter(\.showsTimeOnTheWall))
    func faceOnTheWallShowsTheTime(_ face: Face) throws {
        let now = try #require(render(face, isFrosted: false, offset: 0))
        let later = try #require(render(face, isFrosted: false, offset: Self.later))
        #expect(now != later, "\(face) on the wall did not change with the time")
    }

    /// The frosted face is not empty: it draws the face's own background.
    @Test func frostedFaceKeepsItsColors() throws {
        let modular = try #require(render(.modularAnalog, isFrosted: true, offset: 0))
        let night = try #require(render(.night, isFrosted: true, offset: 0))
        #expect(modular != night)
    }

    /// The face's pixels at a time `offset` from now, from across the room.
    private func render(_ face: Face, isFrosted: Bool, offset: TimeInterval) -> Data? {
        guard let definition = FaceCatalog.definition(face.id) else { return nil }
        var configuration = FaceConfiguration.unsaved(face.id)
        if let style = face.style { configuration.values["style"] = style }
        let services = AppServices.preview()
        let view = definition.makeView()
            .environment(\.faceConfiguration, configuration)
            .environment(\.isFrosted, isFrosted)
            .environment(\.faceTimeOffset, offset)
            .environment(\.faceInsets, EdgeInsets(top: 44, leading: 64, bottom: 44, trailing: 64))
            .environment(\.proximity, .far)
            // ImageRenderer draws no Liquid Glass, so the Home face's clock tile came out empty.
            .environment(\.drawsGlassFlat, true)
            .environment(services)
            .environment(FacesRuntime(services: services))
            .frame(width: 600, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
        return data as Data
    }
}
