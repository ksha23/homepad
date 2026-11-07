import CoreGraphics
import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// A face's mini widget sits in the face's top margin at its leading side,
/// above where any face lays out its content, so neither the face nor its
/// widgets move for it.
@Suite struct FaceMiniWidgetTests {
    private static let glance = MiniWidgetPlacement(widgetID: "shell.glance.mini", size: .small)

    @Test func itFitsTheTopMarginAndStopsShortOfThePills() {
        for screen in FaceWidgetRoomTests.screens {
            for overscan in FaceWidgetRoomTests.overscans {
                let (size, insets) = FaceWidgetRoomTests.wall(screen, overscan: overscan)
                let frame = FaceWidgetSupport.miniWidgetFrame(size: size, insets: insets)
                let label = "\(screen) overscan \(overscan)"
                // In the top margin, ending where the face's content starts, with room above it.
                #expect(frame.maxY == insets.top, "\(label)")
                #expect(frame.minY >= overscan + Theme.Spacing.xs, "\(label)")
                #expect(frame.minX == overscan + Theme.Spacing.screenMargin.leading, "\(label)")
                // A gap before the pills' zone, whether or not they show.
                let pills = FaceWidgetSupport.nowPlayingZone(size: size, insets: insets)
                #expect(frame.maxX + FaceGrid.gap == pills.minX, "\(label)")
                #expect(frame.width > Theme.Size.profileButton, "\(label)")
            }
        }
    }

    @MainActor @Test func theGridIsTheSameWithOrWithoutIt() {
        for definition in FaceCatalog.all where definition.widgets.allowsWidgets {
            for screen in FaceWidgetRoomTests.screens {
                let (size, insets) = FaceWidgetRoomTests.wall(screen, overscan: 0)
                let without = definition.widgets.grid(configuration: FaceConfiguration(faceID: definition.id),
                                                      size: size, insets: insets)
                let with = definition.widgets.grid(
                    configuration: FaceConfiguration(faceID: definition.id, miniWidget: Self.glance),
                    size: size, insets: insets)
                #expect(with.blocked == without.blocked, "\(definition.id) \(screen)")
            }
        }
    }

    @Test func facesSavedBeforeMiniWidgetsHaveNoneAndAChoiceIsSaved() throws {
        let old = #"{"id":"6A1D1C55-0B57-4F0B-9E43-6C5A1B0B2C11","faceID":"faces.modular","values":{},"slots":{},"items":{}}"#
        let face = try JSONDecoder().decode(FaceConfiguration.self, from: Data(old.utf8))
        #expect(face.miniWidget == nil)
        var chosen = face
        chosen.miniWidget = MiniWidgetPlacement(widgetID: "shell.glance.mini", size: .large)
        let saved = try JSONDecoder().decode(FaceConfiguration.self, from: JSONEncoder().encode(chosen))
        #expect(saved.miniWidget == chosen.miniWidget)
        #expect(saved == chosen)
    }

    @Test func aZoneOnTheLeadingSideMovesThatEdgeIn() {
        // A tall narrow corner on the leading side moves the leading edge in, not the top down.
        let insets = Theme.Spacing.screenContent
        let size = CGSize(width: 1210, height: 834)
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 600)
        let beside = insets.clearing(narrow, in: size)
        #expect(beside.leading == narrow.maxX && beside.top == insets.top && beside.trailing == insets.trailing)
    }

    @Test func theDebugArgumentNamesAWidgetAndASize() {
        #expect(FaceDebugOptions.miniWidget(from: "shell.glance.mini:medium")
            == MiniWidgetPlacement(widgetID: "shell.glance.mini", size: .medium))
        #expect(FaceDebugOptions.miniWidget(from: "shell.glance.mini") == Self.glance)
        #expect(FaceDebugOptions.miniWidget(from: "off") == nil)
    }
}
