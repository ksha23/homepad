import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// The Music app opens where it was left: its section, the Library's kind and
/// the page on top. Launch arguments win and leave the saved place alone.
@MainActor @Suite struct MusicPlaceTests {
    private let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.place.\(UUID())")!)
    /// No launch arguments.
    private let noArguments = UserDefaults(suiteName: "audio.place.args.\(UUID())")!

    private static let nightSignals = DemoMusicCatalog.albums.first { $0.name == "Night Signals" }!

    @Test func startsOnListenNowAndPlaylists() {
        let place = MusicPlace(settings: settings, launchArguments: noArguments)
        #expect(place.section == .listenNow)
        #expect(place.libraryKind == .playlists)
        #expect(place.pageToReopen() == nil)
    }

    @Test func comesBackAfterARestart() {
        let place = MusicPlace(settings: settings, launchArguments: noArguments)
        place.section = .library
        place.libraryKind = .albums
        place.save(page: .demo(Self.nightSignals))

        let restarted = MusicPlace(settings: settings, launchArguments: noArguments)
        #expect(restarted.section == .library)
        #expect(restarted.libraryKind == .albums)
        let page = restarted.pageToReopen()
        #expect(page?.source == .demo)
        #expect(page?.kind == .album)
        #expect(page?.title == "Night Signals")
        #expect(restarted.pageToReopen() == nil, "the saved page comes back once per launch")
    }

    @Test func closingThePageForgetsIt() {
        let place = MusicPlace(settings: settings, launchArguments: noArguments)
        place.save(page: .demo(Self.nightSignals))
        place.save(page: nil)
        #expect(MusicPlace(settings: settings, launchArguments: noArguments).pageToReopen() == nil)
    }

    @Test func launchArgumentsWinAndSaveNothing() {
        let saved = MusicPlace(settings: settings, launchArguments: noArguments)
        saved.section = .radio
        saved.save(page: .demo(Self.nightSignals))

        let arguments = UserDefaults(suiteName: "audio.place.pinned.\(UUID())")!
        arguments.set("search", forKey: "HomePadMusicSection")
        let pinned = MusicPlace(settings: settings, launchArguments: arguments)
        #expect(pinned.section == .search)
        #expect(pinned.pageToReopen() == nil, "a pinned section shows its own page")
        pinned.section = .sleep
        pinned.save(page: nil)

        let next = MusicPlace(settings: settings, launchArguments: noArguments)
        #expect(next.section == .radio)
        #expect(next.pageToReopen()?.title == "Night Signals")
    }

    @Test func thePageStackSavesItsTopPage() {
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: true)
        media.pages.push(.demo(Self.nightSignals))
        #expect(settings[MusicPlace.pageKey]?.title == "Night Signals")
        media.pages.pop()
        #expect(settings[MusicPlace.pageKey] == nil)
    }
}
