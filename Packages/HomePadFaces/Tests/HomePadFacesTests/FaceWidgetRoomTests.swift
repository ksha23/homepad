import CoreGraphics
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadFaces

/// Faces whose content fills the screen keep it beside their widget area
/// while they have widgets, so no widget ever covers the time at any distance.
@Suite struct FaceWidgetRoomTests {
    /// Kyle's iPads and the simulators, in both orientations.
    static let screens = [
        CGSize(width: 1210, height: 834), CGSize(width: 834, height: 1210),
        CGSize(width: 1376, height: 1032), CGSize(width: 1032, height: 1376),
        CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366),
        CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194),
    ]
    /// The burn-in shift amounts: off, Subtle, Standard and Strong.
    static let overscans: [CGFloat] = [0, 4, 8, 12]

    /// The face as the wall lays it out: larger than the screen by the
    /// overscan on every side, with the overscan added to the insets.
    static func wall(_ screen: CGSize, overscan: CGFloat) -> (size: CGSize, insets: EdgeInsets) {
        let base = Theme.Spacing.screenContent
        return (CGSize(width: screen.width + overscan * 2, height: screen.height + overscan * 2),
                EdgeInsets(top: base.top + overscan, leading: base.leading + overscan,
                           bottom: base.bottom + overscan, trailing: base.trailing + overscan))
    }

    static func content(_ size: CGSize, _ insets: EdgeInsets) -> CGRect {
        CGRect(x: insets.leading, y: insets.top, width: size.width - insets.leading - insets.trailing,
               height: size.height - insets.top - insets.bottom)
    }

    /// The face insets `HostedFace` hands a face: the wall's, plus the room its widgets take.
    static func insets(_ support: FaceWidgetSupport, size: CGSize, base: EdgeInsets, hasWidgets: Bool) -> EdgeInsets {
        let room = support.widgetRoom(size: size, insets: base, hasWidgets: hasWidgets)
        return EdgeInsets(top: base.top + room.top, leading: base.leading + room.leading,
                          bottom: base.bottom + room.bottom, trailing: base.trailing + room.trailing)
    }

    /// The open cells of a face's grid as rects, where widgets may go.
    static func openFrames(_ support: FaceWidgetSupport, faceID: String, size: CGSize, insets: EdgeInsets) -> [CGRect] {
        let grid = support.grid(configuration: FaceConfiguration(faceID: faceID), size: size, insets: insets)
        return grid.openCells.map(grid.frame(for:))
    }

    @MainActor @Test func withoutWidgetsAFaceKeepsTheWholeScreen() {
        for definition in FaceCatalog.all {
            let room = definition.widgets.widgetRoom(size: CGSize(width: 1210, height: 834),
                                                     insets: Theme.Spacing.screenContent, hasWidgets: false)
            #expect(room == EdgeInsets(), "\(definition.id)")
        }
    }

    @MainActor @Test func contentBesideWidgetsEndsAGapBeforeThem() {
        for definition in FaceCatalog.all where definition.widgets.widgetArea != nil {
            for screen in Self.screens {
                for overscan in Self.overscans {
                    let (size, base) = Self.wall(screen, overscan: overscan)
                    let content = Self.content(size, Self.insets(definition.widgets, size: size, base: base, hasWidgets: true))
                    let label = "\(definition.id) \(screen) overscan \(overscan)"
                    #expect(content.width > size.width * 0.5 && content.height > size.height * 0.4, "\(label)")
                    for cell in Self.openFrames(definition.widgets, faceID: definition.id, size: size, insets: base) {
                        let gap = max(cell.minX - content.maxX, cell.minY - content.maxY)
                        #expect(gap >= FaceGrid.gap - 0.5, "\(label) cell \(cell)")
                    }
                }
            }
        }
    }

    @MainActor @Test func modularWidgetsSitBesideInLandscapeAndBelowInPortrait() throws {
        let support = try #require(FaceCatalog.definition("faces.modular")).widgets
        let base = Theme.Spacing.screenContent
        let wide = CGSize(width: 1366, height: 1024)
        let landscape = ModularLayout(size: wide, insets: Self.insets(support, size: wide, base: base, hasWidgets: true))
        let column = Self.openFrames(support, faceID: "faces.modular", size: wide, insets: base)
        // Two columns of four, less the top trailing cell under the profile button.
        #expect(column.count == 7)
        #expect(column.allSatisfy { $0.minX > landscape.info.maxX })
        let tall = CGSize(width: 1024, height: 1366)
        let portrait = ModularLayout(size: tall, insets: Self.insets(support, size: tall, base: base, hasWidgets: true))
        let rows = Self.openFrames(support, faceID: "faces.modular", size: tall, insets: base)
        #expect(rows.count == 8)
        #expect(rows.allSatisfy { $0.minY > portrait.info.maxY })
    }

    @MainActor @Test func thePhotosTimeStaysAboveItsWidgetsAtEveryDistance() throws {
        let support = try #require(FaceCatalog.definition("faces.photos")).widgets
        let metrics = ClockFontMetrics.sample
        for screen in Self.screens {
            for overscan in Self.overscans {
                let (size, base) = Self.wall(screen, overscan: overscan)
                let insets = Self.insets(support, size: size, base: base, hasWidgets: true)
                let top = Self.openFrames(support, faceID: "faces.photos", size: size, insets: base).map(\.minY).min() ?? size.height
                let label = "\(screen) overscan \(overscan)"
                for layout in [PhotoClockLayout.depth(viewSize: size, insets: insets, metrics: metrics),
                               PhotoClockLayout.classic(viewSize: size, insets: insets, metrics: metrics)] {
                    for isNear in [false, true] {
                        let digits = layout.digits(isNear: isNear)
                        #expect(digits.maxY * size.height + FaceGrid.gap <= top + 0.5, "time \(label) near \(isNear)")
                    }
                    #expect(layout.date.maxY + FaceGrid.gap <= top + 0.5, "date \(label)")
                }
            }
        }
    }

    @MainActor @Test func photosWidgetsTakeTheBottomRowInLandscapeAndThreeRowsInPortrait() throws {
        let support = try #require(FaceCatalog.definition("faces.photos")).widgets
        let base = Theme.Spacing.screenContent
        #expect(Self.openFrames(support, faceID: "faces.photos", size: CGSize(width: 1210, height: 834), insets: base).count == 6)
        #expect(Self.openFrames(support, faceID: "faces.photos", size: CGSize(width: 834, height: 1210), insets: base).count == 12)
    }

    /// A tall widget fits the widget column of every face with a widget area in
    /// landscape, and the three bottom rows of Photos in portrait, as the README says.
    @MainActor @Test func tallWidgetsFitTheColumnInLandscapeAndPhotosInPortrait() throws {
        let base = Theme.Spacing.screenContent
        let photos = try #require(FaceCatalog.definition("faces.photos")).widgets
        for screen in Self.screens {
            let isLandscape = screen.width > screen.height
            // Photos keeps its widget area along the bottom in both orientations.
            for definition in FaceCatalog.all where definition.widgets.widgetArea != nil && definition.id != "faces.photos" {
                let grid = definition.widgets.grid(configuration: FaceConfiguration(faceID: definition.id), size: screen, insets: base)
                #expect(grid.hasRoom(for: .tall) == isLandscape, "\(definition.id) \(screen)")
            }
            let grid = photos.grid(configuration: FaceConfiguration(faceID: "faces.photos"), size: screen, insets: base)
            #expect(grid.hasRoom(for: .tall) == !isLandscape, "faces.photos \(screen)")
        }
    }

    @MainActor @Test func theDialFacesKeepTheirDialAndLeaveRoomAround() throws {
        for faceID in ["faces.analog", "faces.fade", "faces.numerals"] {
            let support = try #require(FaceCatalog.definition(faceID)).widgets
            #expect(support.widgetArea == nil, "\(faceID)")
            for screen in Self.screens {
                let open = Self.openFrames(support, faceID: faceID, size: screen, insets: Theme.Spacing.screenContent)
                // A column on each side in landscape, less the cell under the profile
                // button. In portrait a row below, and the leading corner of the row
                // above, beside the Now Playing pill. The trailing one is the button's.
                #expect(open.count >= (screen.width > screen.height ? 6 : 4), "\(faceID) \(screen) open \(open.count)")
                if screen.height > screen.width {
                    let grid = support.grid(configuration: FaceConfiguration(faceID: faceID), size: screen,
                                            insets: Theme.Spacing.screenContent)
                    #expect(grid.hasRoom(for: .medium), "\(faceID) \(screen)")
                }
            }
        }
    }

    @MainActor @Test func noWidgetEverSitsUnderTheNowPlayingPill() {
        for definition in FaceCatalog.all where definition.widgets.allowsWidgets {
            for screen in Self.screens {
                for overscan in Self.overscans {
                    let (size, base) = Self.wall(screen, overscan: overscan)
                    let pill = FaceWidgetSupport.nowPlayingZone(size: size, insets: base)
                    let label = "\(definition.id) \(screen) overscan \(overscan)"
                    for cell in Self.openFrames(definition.widgets, faceID: definition.id, size: size, insets: base) {
                        #expect(!cell.insetBy(dx: 12, dy: 12).intersects(pill), "\(label) cell \(cell)")
                    }
                }
            }
        }
    }

    @MainActor @Test func thePillTakesNoCellFromAWidgetArea() {
        // Columns on the trailing side and rows along the bottom never reach the top center.
        // The profile button's corner is blocked either way.
        for definition in FaceCatalog.all where definition.widgets.widgetArea != nil {
            for screen in Self.screens {
                let base = Theme.Spacing.screenContent
                let grid = definition.widgets.grid(configuration: FaceConfiguration(faceID: definition.id), size: screen,
                                                   insets: base)
                let withoutPill = FaceGrid(size: screen, insets: base, protecting: [
                    definition.widgets.widgetArea!.contentFrame(on: FaceGrid(size: screen, insets: base)),
                    FaceWidgetSupport.profileZone(size: screen, insets: base),
                ])
                #expect(grid.blocked == withoutPill.blocked, "\(definition.id) \(screen)")
            }
        }
    }

    @MainActor @Test func analogNumeralsFollowTheFaceAndKeepToTheDialWithWidgets() {
        let region = AnalogFace.definition.widgets.region
        for screen in Self.screens {
            let (size, insets) = Self.wall(screen, overscan: 8)
            let content = Self.content(size, insets)
            // Without widgets the numerals take the whole face inside the insets.
            #expect(AnalogFace.numeralBounds(size: size, insets: insets, keepClear: EdgeInsets(), region: nil) == content)
            // With widgets they keep inside the dial's region, whose cells no widget covers.
            let dial = region.rects(configuration: FaceConfiguration(faceID: "faces.analog"), size: size, insets: insets)[0]
            let bounds = AnalogFace.numeralBounds(size: size, insets: insets, keepClear: EdgeInsets(), region: dial)
            #expect(dial.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(screen)")
            // With the Now Playing pill they shrink at the top and the bottom alike, and stay centered.
            let pill = Theme.Size.faceNowPlayingRoom
            let withPill = EdgeInsets(top: insets.top + pill, leading: insets.leading, bottom: insets.bottom,
                                      trailing: insets.trailing)
            let shrunk = AnalogFace.numeralBounds(size: size, insets: withPill,
                                                  keepClear: EdgeInsets(top: pill, leading: 0, bottom: 0, trailing: 0),
                                                  region: nil)
            #expect(abs(shrunk.midY - size.height / 2) < 0.5, "\(screen)")
            #expect(abs(shrunk.height - (content.height - pill * 2)) < 0.5, "\(screen)")
        }
    }
}
