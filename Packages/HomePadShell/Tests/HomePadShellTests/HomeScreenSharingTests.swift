import Foundation
import HomePadCore
import HomePadUI
import Testing
@testable import HomePadShell

/// The Home Screens and wallpapers HomePads share, and how one layout lands on
/// each iPad size.
@MainActor @Suite struct HomeScreenSharingTests {
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test.homeSharing.\(UUID())")!)
    }

    private func sampleLayout() -> HomeScreenLayout {
        var layout = HomeScreenLayout(pages: [[.widget("personal.weather", size: .large), .app("music"), .app("home")],
                                              [.app("calendar")]],
                                      knownAppIDs: ["music", "home", "calendar", "timers", "photos", "recipes"])
        layout.setMiniWidget(nil)
        return layout
    }

    @Test func aLayoutReadsTheSameEveryTimeAndAppliesAsItWasShared() throws {
        let kyle = UUID()
        let here = makeSettings()
        here[ShellSettings.homeScreenLayout(for: kyle)] = sampleLayout()
        let first = HomeScreenSharing.readLayout(.member(kyle), settings: here)
        // Read again from storage, the known apps (a set) come out in the same order.
        let second = HomeScreenSharing.readLayout(.member(kyle), settings: here)
        #expect(first == second)
        guard case .content(let content) = first else {
            Issue.record("No layout to share")
            return
        }

        let there = makeSettings()
        HomeScreenSharing.applyLayout(content, for: .member(kyle), settings: there)
        #expect(there[ShellSettings.homeScreenLayout(for: kyle)] == sampleLayout())
        #expect(HomeScreenSharing.readLayout(.member(kyle), settings: there) == first)

        // A layout reset to the default is a deletion.
        HomeScreenSharing.applyLayout(nil, for: .member(kyle), settings: there)
        #expect(HomeScreenSharing.readLayout(.member(kyle), settings: there) == .none)
        #expect(HomeScreenSharing.readLayout(.household, settings: there) == .none)
    }

    @Test func aPhotoWallpaperStaysOnThisIPad() {
        let settings = makeSettings()
        #expect(HomeScreenSharing.readWallpaper(.household, settings: settings) == .none)
        settings[ShellSettings.wallpaper(for: nil)] = .ocean
        #expect(HomeScreenSharing.readWallpaper(.household, settings: settings) == .content("ocean"))
        settings[ShellSettings.wallpaper(for: nil)] = .photo
        #expect(HomeScreenSharing.readWallpaper(.household, settings: settings) == .onlyThisHomePad)

        // A gradient chosen on another HomePad later replaces the photo, and a photo never arrives.
        HomeScreenSharing.applyWallpaper("dusk", for: .household, settings: settings)
        #expect(settings[ShellSettings.wallpaper(for: nil)] == .dusk)
        HomeScreenSharing.applyWallpaper("photo", for: .household, settings: settings)
        #expect(settings[ShellSettings.wallpaper(for: nil)] == .dusk)
    }

    @Test func aPersonsHomeScreenAndPhotoFollowTheirNewID() throws {
        let settings = makeSettings()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wallpapers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = WallpaperPhotoStore.Files(directory: folder)
        let old = UUID(), new = UUID()
        settings[ShellSettings.homeScreenLayout(for: old)] = sampleLayout()
        settings[ShellSettings.wallpaper(for: old)] = .photo
        try Data("jpeg".utf8).write(to: files.url(for: old.uuidString))

        HomeScreenSharing.moveMember(from: old, to: new, settings: settings, photos: files)
        #expect(settings[ShellSettings.homeScreenLayout(for: new)] == sampleLayout())
        #expect(!settings.contains(ShellSettings.homeScreenLayout(for: old)))
        #expect(settings[ShellSettings.wallpaper(for: new)] == .photo)
        #expect(FileManager.default.fileExists(atPath: files.url(for: new.uuidString).path))
        #expect(!FileManager.default.fileExists(atPath: files.url(for: old.uuidString).path))
    }

    // MARK: Screen sizes

    /// The Home Screen's page area in landscape and portrait, roughly as each iPad lays it out.
    private static let pages: [(name: String, landscape: CGSize, portrait: CGSize)] = [
        ("11-inch", CGSize(width: 1138, height: 650), CGSize(width: 778, height: 1010)),
        ("12.9-inch", CGSize(width: 1286, height: 832), CGSize(width: 944, height: 1176)),
        ("13-inch", CGSize(width: 1294, height: 840), CGSize(width: 950, height: 1184)),
    ]

    @Test func everyIPadHasTheSameColumnsAndAsManyRowsAsItsScreenHolds() {
        let landscape = Self.pages.map { HomeGridMetrics(size: $0.landscape, prefersLargerCells: false) }
        let portrait = Self.pages.map { HomeGridMetrics(size: $0.portrait, prefersLargerCells: false) }
        #expect(landscape.allSatisfy { $0.columns == 6 })
        #expect(portrait.allSatisfy { $0.columns == 4 })
        #expect(landscape.map(\.rows) == [3, 4, 4])
        #expect(portrait.allSatisfy { $0.rows == 5 })
    }

    @Test func aPageThatFillsALargeScreenGoesOnToTheNextScreenOfASmallOne() {
        // A large widget and twenty apps: one full screen on a 13-inch iPad in landscape.
        let spans = [GridSpan(.large)] + Array(repeating: GridSpan.one, count: 20)
        let large = HomeGridMetrics(size: Self.pages[2].landscape, prefersLargerCells: false)
        let small = HomeGridMetrics(size: Self.pages[0].landscape, prefersLargerCells: false)
        let onLarge = GridPacker.paginate(spans, columns: large.columns, rows: large.rows)
        let onSmall = GridPacker.paginate(spans, columns: small.columns, rows: small.rows)
        #expect(onLarge.map(\.count) == [21])
        #expect(onSmall.map(\.count) == [15, 6])
        // Same order on both: the 11-inch shows the rest on its next screen.
        #expect(onSmall.flatMap { $0.map(\.index) } == Array(0..<21))
    }
}
