import Foundation
import SwiftUI
import Testing
import UIKit
@testable import HomePadUI

/// Headers keep the top center free for the Now Playing pill at every iPad
/// width, and give way like an iPadOS toolbar when a side runs out of room.
@MainActor
struct HeaderLayoutTests {
    /// Header row widths: the screen less the shell's margin and a screen's padding.
    nonisolated static let widths: [CGFloat] = [
        834 - 128, // 11-inch portrait
        1032 - 128, // 13-inch portrait
        1210 - 128, // 11-inch landscape
        1376 - 128, // 13-inch landscape
    ]

    @Test func sidesSplitWhatTheZoneLeaves() {
        #expect(HeaderMetrics.sideWidth(rowWidth: 706) == 265)
        #expect(HeaderMetrics.sideWidth(rowWidth: 1082) == 453)
        #expect(HeaderMetrics.sideWidth(rowWidth: 100) == 0)
        #expect(HeaderMetrics.titleRoom(rowWidth: 706, hasBackButton: true) == 265 - Theme.Size.toolbarItem - Theme.Spacing.s)
    }

    /// A sheet's toolbar takes what a short title leaves. A long title keeps
    /// 60 percent, and the toolbar keeps room for Post and the close button.
    @Test func sheetSidesFollowTheTitle() {
        func expectSides(_ sides: (leading: CGFloat, trailing: CGFloat), _ leading: CGFloat, _ trailing: CGFloat,
                         sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(abs(sides.leading - leading) < 0.001, "leading \(sides.leading)", sourceLocation: sourceLocation)
            #expect(abs(sides.trailing - trailing) < 0.001, "trailing \(sides.trailing)", sourceLocation: sourceLocation)
        }
        // A form sheet with a short title: the toolbar gets the rest.
        expectSides(HeaderSplit.sheet.sides(rowWidth: 532, titleWidth: 200), 200, 308)
        // A long title: 60 and 40 percent of what the gap leaves.
        expectSides(HeaderSplit.sheet.sides(rowWidth: 532, titleWidth: 400), 304.8, 203.2)
        expectSides(HeaderSplit.sheet.sides(rowWidth: 532), 304.8, 203.2)
        // An iPhone: Post and the close button keep their 160 points.
        expectSides(HeaderSplit.sheet.sides(rowWidth: 345, titleWidth: 250), 161, 160)
        // Narrower still: halves.
        expectSides(HeaderSplit.sheet.sides(rowWidth: 200), 88, 88)
        // Only the close button.
        expectSides(HeaderSplit.sheetCloseOnly.sides(rowWidth: 532), 532 - 24 - Theme.Size.toolbarItem, Theme.Size.toolbarItem)
        // An app keeps its halves around the pill whatever its title.
        expectSides(HeaderSplit.app.sides(rowWidth: 706, titleWidth: 100), 265, 265)
    }

    @Test func stagesMoveLowPriorityItemsFirstAndNeverTheProminentOne() {
        #expect(!ToolbarStage.compact.movesToMenu(.low, isProminent: false))
        #expect(ToolbarStage.overflow.movesToMenu(.low, isProminent: false))
        #expect(!ToolbarStage.overflow.movesToMenu(.high, isProminent: false))
        #expect(ToolbarStage.minimal.movesToMenu(.high, isProminent: false))
        #expect(!ToolbarStage.minimal.movesToMenu(.high, isProminent: true))
    }

    @Test(arguments: widths)
    func calendarHeaderStaysOutOfTheZone(width: CGFloat) {
        let log = FrameLog()
        render(width: width, name: "calendar-\(Int(width))") {
            calendarHeader(log)
        }
        #expect(log.frames["add"] != nil, "the prominent action always shows")
        #expect(log.frames["picker"] != nil)
        expectClearOfZone(log, width: width)
    }

    /// Also covers a lone trailing closure, which must be the toolbar. The
    /// items are icons in every stage but the first, so the stage each width
    /// takes follows from the 48 point items and the spacing alone.
    @Test(arguments: widths)
    func crowdedToolbarMovesItemsIntoMore(width: CGFloat) {
        let log = FrameLog()
        render(width: width, name: "crowded-\(Int(width))") {
            AppHeader("Family Board", onClose: {}) {
                GlassCapsuleButton("One", systemImage: "star") {}.probe("one", log).toolbarItemPriority(.low)
                GlassCapsuleButton("Two", systemImage: "star") {}.probe("two", log).toolbarItemPriority(.low)
                GlassCapsuleButton("Three", systemImage: "star") {}.probe("three", log)
                GlassCapsuleButton("Four", systemImage: "star") {}.probe("four", log)
                GlassCapsuleButton("Five", systemImage: "star") {}.probe("five", log)
                GlassCapsuleButton("Six", systemImage: "star") {}.probe("six", log).toolbarItemPriority(.low)
                GlassIconButton("plus", label: "New Note", isProminent: true) {}.probe("add", log)
            }
        }
        // Compact needs 8 items and 7 gaps (454 points), overflow 6 and 5 (338), minimal 3 and 2 (164).
        let expected: Set<String> = switch HeaderMetrics.sideWidth(rowWidth: width) {
        case 454...: ["one", "two", "three", "four", "five", "six", "add"]
        case 338...: ["three", "four", "five", "add"]
        default: ["add"]
        }
        #expect(Set(log.frames.keys) == expected)
        expectClearOfZone(log, width: width)
    }

    @Test(arguments: widths)
    func longTitleShrinksBeforeTheZone(width: CGFloat) {
        let log = FrameLog()
        render(width: width, name: "long-title-\(Int(width))") {
            AppHeader("Grandma's 80th Birthday at the Lake House", onBack: {}, onClose: {}) {
                GlassIconButton("play.fill", label: "Play", isProminent: true) {}.probe("play", log)
            } titleAccessory: {
                picker.probe("picker", log)
            }
            .dynamicTypeSize(.xxxLarge)
        }
        #expect(log.frames["play"] != nil)
        #expect(log.frames["picker"] != nil)
        expectClearOfZone(log, width: width)
    }

    @Test(arguments: widths)
    func detailHeaderStaysOutOfTheZone(width: CGFloat) {
        let log = FrameLog()
        render(width: width, name: "detail-\(Int(width))") {
            DetailHeader("Butternut Squash Soup With a Very Long Name", subtitle: "Step 2 of 7", onClose: {}, trailing: {
                GlassIconButton("speaker.wave.2.fill", label: "Mute") {}.probe("mute", log)
            })
        }
        #expect(log.frames["mute"] != nil)
        expectClearOfZone(log, width: width)
    }

    /// A whole screen, so the header sits in `AppScreen`'s stack, which asks
    /// it about several heights before placing it.
    @Test(arguments: widths)
    func appScreenHeaderStaysOutOfTheZone(width: CGFloat) {
        let log = FrameLog()
        let padding = Theme.Spacing.l
        render(width: width + padding * 2, height: 600, name: "screen-\(Int(width))") {
            AppScreen("September 2026", onClose: {}) {
                calendarItems(log)
            } titleAccessory: {
                picker.probe("picker", log)
            } content: {
                Text("Team standup").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        #expect(log.frames["add"] != nil)
        #expect(log.frames["picker"] != nil)
        expectClearOfZone(log, width: width, origin: padding)
    }

    /// A header in a window, laid out by UIKit as on the iPad rather than by
    /// `ImageRenderer`. This is where the Faces freeze shows on iOS 27: a
    /// header that measures its toolbar stages at changing widths never
    /// finishes `layoutIfNeeded`, so such a change hangs this test.
    @Test(arguments: widths)
    func headerInAWindowStaysOutOfTheZone(width: CGFloat) async throws {
        let log = FrameLog()
        let host = UIHostingController(rootView: calendarHeader(log)
            .coordinateSpace(.named(FrameLog.space))
            .frame(width: width)
            .environment(\.colorScheme, .dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 200))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        #expect(log.frames["add"] != nil)
        #expect(log.frames["picker"] != nil)
        expectClearOfZone(log, width: width)
    }

    // MARK: Sheets

    /// Sheet header widths: an iPhone sheet, iPad form sheets and a page sheet,
    /// less the sheet's padding.
    nonisolated static let sheetWidths: [CGFloat] = [393 - 48, 540 - 48, 704 - 48, 960 - 48]

    /// The title and the one prominent action share the row with no Now
    /// Playing zone. A disabled action still shows, dimmed. A lone trailing
    /// closure is the toolbar, not `onBack`, which comes before it.
    @Test(arguments: sheetWidths)
    func sheetHeaderKeepsItsActionInItsSide(width: CGFloat) {
        let log = FrameLog()
        render(width: width, name: "sheet-\(Int(width))") {
            SheetHeader("New Note") {
                GlassCapsuleButton("Post", isProminent: true) {}.disabled(true).probe("post", log)
            }
        }
        #expect(log.frames["post"] != nil, "a disabled action still shows")
        expectClearOfZone(log, width: width, split: .sheet, titleWidth: sheetTitleWidth("New Note"))
    }

    /// Beside a short title the toolbar takes the room the title leaves, so
    /// an action with a symbol keeps its words in an iPad form sheet.
    @Test func shortTitleLeavesRoomForTheActionsWords() {
        let log = FrameLog()
        let width: CGFloat = 580 - 48
        render(width: width, name: "sheet-short-title") {
            SheetHeader("Ingredients") {
                GlassCapsuleButton("Add 12 to Groceries", systemImage: "cart.badge.plus", isProminent: true) {}.probe("add", log)
            }
        }
        let add = log.frames["add"]
        #expect((add?.width ?? 0) > 120, "the action shows its title, not only its symbol")
        expectClearOfZone(log, width: width, split: .sheet, titleWidth: sheetTitleWidth("Ingredients"))
    }

    /// The first of two trailing closures is the toolbar, and a lone one is the content.
    @Test func sheetScreenClosuresAreTheToolbarAndTheContent() {
        let log = FrameLog()
        render(width: 600, height: 300, name: "sheet-closures") {
            VStack {
                SheetScreen("Add Station") {
                    GlassCapsuleButton("Add", isProminent: true) {}.probe("add", log)
                } content: {
                    Text("Form").probe("form", log)
                }
                SheetScreen("Wallpaper") {
                    Text("Grid").probe("grid", log)
                }
            }
        }
        #expect(log.frames["add"] != nil)
        #expect(log.frames["form"] != nil)
        #expect(log.frames["grid"] != nil)
    }

    /// A sheet's toolbar gives way like an app's when its side is short of room.
    @Test(arguments: sheetWidths)
    func crowdedSheetToolbarMovesItemsIntoMore(width: CGFloat) {
        let log = FrameLog()
        render(width: width, name: "sheet-crowded-\(Int(width))") {
            SheetHeader("Calendars", onBack: {}, onClose: {}) {
                GlassCapsuleButton("Show All", systemImage: "eye") {}.probe("show", log)
                GlassCapsuleButton("Hide All", systemImage: "eye.slash") {}.probe("hide", log)
                GlassCapsuleButton("Save", isProminent: true) {}.probe("save", log)
            }
        }
        #expect(log.frames["save"] != nil, "the prominent action always shows")
        // Show All and Hide All as symbols, Save and the close button.
        let titleWidth = sheetTitleWidth("Calendars", hasBackButton: true)
        if HeaderSplit.sheet.sides(rowWidth: width, titleWidth: titleWidth).trailing >= 4 * Theme.Size.toolbarItem + 3 * Theme.Spacing.s + 60 {
            #expect(log.frames["show"] != nil && log.frames["hide"] != nil)
        }
        expectClearOfZone(log, width: width, split: .sheet, titleWidth: titleWidth)
    }

    /// A whole sheet in a window, laid out by UIKit, with a list under the
    /// header, so a change that makes the stages measure at changing widths
    /// hangs here as the Faces freeze did.
    @Test(arguments: sheetWidths)
    func sheetScreenInAWindowSettles(width: CGFloat) async throws {
        let log = FrameLog()
        let screen = SheetScreen("Add Station", onClose: {}) {
            GlassCapsuleButton("Add", isProminent: true) {}.probe("add", log)
        } content: {
            List {
                Text("Name")
                Text("Stream URL")
            }
        }
        let host = UIHostingController(rootView: screen
            .coordinateSpace(.named(FrameLog.space))
            .frame(width: width + 2 * Theme.Spacing.l)
            .environment(\.colorScheme, .dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width + 2 * Theme.Spacing.l, height: 600))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        #expect(log.frames["add"] != nil)
        expectClearOfZone(log, width: width, origin: Theme.Spacing.l, split: .sheet, titleWidth: sheetTitleWidth("Add Station"))
    }

    // MARK: Helpers

    private var picker: some View {
        HeaderPicker("View", selection: .constant(1), title: "Month", systemImage: "calendar") {
            Text("Day").tag(0)
            Text("Month").tag(1)
        }
    }

    @ViewBuilder
    private func calendarItems(_ log: FrameLog) -> some View {
        ToolbarGroup {
            GlassIconButton("chevron.left", label: "Previous") {}.probe("previous", log)
            GlassCapsuleButton("Today") {}.probe("today", log)
            GlassIconButton("chevron.right", label: "Next") {}.probe("next", log)
        }
        GlassIconButton("plus", label: "Add Event", isProminent: true) {}.probe("add", log)
    }

    private func calendarHeader(_ log: FrameLog) -> some View {
        AppHeader("September 2026", onClose: {}) {
            calendarItems(log)
        } titleAccessory: {
            picker.probe("picker", log)
        }
    }

    /// Lays the header out at a row width, and a height when given. With
    /// `HOMEPAD_HEADER_SNAPSHOTS` set (`TEST_RUNNER_HOMEPAD_HEADER_SNAPSHOTS`
    /// for xcodebuild), it also writes a PNG there to look at.
    private func render<Header: View>(
        width: CGFloat, height: CGFloat? = nil, name: String, @ViewBuilder header: () -> Header
    ) {
        let renderer = ImageRenderer(content: header()
            .coordinateSpace(.named(FrameLog.space))
            .frame(width: width, height: height)
            .padding(.vertical, Theme.Spacing.m)
            .background(.black)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = renderer.uiImage
        if let folder = ProcessInfo.processInfo.environment["HOMEPAD_HEADER_SNAPSHOTS"], let data = image?.pngData() {
            try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }

    /// What a sheet's title side needs, measured as `SheetHeader` measures it,
    /// in the large title font at the default text size.
    private func sheetTitleWidth(_ title: String, hasBackButton: Bool = false) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .largeTitle)
        let font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: 0)
        let text = (title as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        return text + Theme.Spacing.xs + (hasBackButton ? Theme.Size.toolbarItem + Theme.Spacing.s : 0)
    }

    /// Checks that every probed item sits in a side of a row that starts at
    /// `origin`, clear of the center between the sides. A sheet's sides follow
    /// its title, measured here to within a couple of points.
    private func expectClearOfZone(
        _ log: FrameLog, width: CGFloat, origin: CGFloat = 0, split: HeaderSplit = .app, titleWidth: CGFloat? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let sides = split.sides(rowWidth: width, titleWidth: titleWidth)
        let tolerance: CGFloat = titleWidth == nil ? 0.5 : 2
        for (name, global) in log.frames {
            let frame = global.offsetBy(dx: -origin, dy: 0)
            let isLeading = frame.maxX <= sides.leading + tolerance
            let isTrailing = frame.minX >= width - sides.trailing - tolerance
            #expect(isLeading || isTrailing, "\(name) at \(frame) enters the center of the row", sourceLocation: sourceLocation)
            #expect(frame.minX >= -0.5 && frame.maxX <= width + 0.5, "\(name) at \(frame) leaves the row", sourceLocation: sourceLocation)
        }
    }
}

/// Frames of the probed items, recorded as the header lays them out.
final class FrameLog: @unchecked Sendable {
    static let space = "header"
    var frames: [String: CGRect] = [:]

    func record(_ name: String, _ frame: CGRect) {
        frames[name] = frame
    }
}

private extension View {
    /// Records this view's frame in the header's coordinate space when it is
    /// laid out in the bar. Menu content and the toolbar stages a header only
    /// measures are laid out away from the header, where its coordinate space
    /// is missing, so they are not recorded.
    func probe(_ name: String, _ log: FrameLog) -> some View {
        modifier(FrameProbe(name: name, log: log))
    }
}

private struct FrameProbe: ViewModifier {
    let name: String
    let log: FrameLog
    @Environment(\.toolbarPlacement) private var placement

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                if !placement.isMenu, proxy.bounds(of: .named(FrameLog.space)) != nil {
                    let _ = log.record(name, proxy.frame(in: .global))
                }
                Color.clear
            }
        }
    }
}
