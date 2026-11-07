import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// The simulator's pretend Music Assistant answers through the same decoders and
/// changes its speakers like the real one.
@MainActor @Suite struct DemoMusicAssistantTests {
    private let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.demo.\(UUID())")!)

    @Test func answersDiscoverySearchAndLibrary() async throws {
        let home = DemoMusicAssistantHome()
        let service = MusicAssistantService(settings: settings, remote: RemotePlayerController { home }) { home }
        await service.refreshStatus()
        #expect(service.isReady)
        #expect(service.players.map(\.name) == ["Bedroom", "Kitchen", "Living Room HomePods", "Office Sonos"])
        await service.search("neon")
        #expect(service.searchResults?.artists.map(\.name) == ["Neon Avenue"])
        await service.loadHome()
        #expect(!service.home.playlists.isEmpty)
        let favorites = service.home.favoriteTracks
        #expect(!favorites.isEmpty)
        #expect(favorites.filter { !$0.isFavorite }.isEmpty)
    }

    @Test func playsMovesAndGroups() async throws {
        let home = DemoMusicAssistantHome()
        let service = MusicAssistantService(settings: settings, remote: RemotePlayerController { home }) { home }
        await service.refreshStatus()
        let living = try #require(service.players.first { $0.name == "Living Room HomePods" })
        #expect(living.isPlaying)
        #expect(service.groupMembers(of: living).map(\.name) == ["Kitchen"])

        let bedroom = try #require(service.players.first { $0.name == "Bedroom" })
        try await service.play(DemoMusicCatalog.playlists[0], on: bedroom.id)
        #expect(service.player(bedroom.id)?.isPlaying == true)
        #expect(service.player(bedroom.id)?.title != nil)

        try await service.playOn([bedroom.id, living.id])
        let leader = try #require(service.player(bedroom.id))
        #expect(service.groupMembers(of: leader).map(\.name).contains("Living Room HomePods"))
        let queue = await service.queue(for: bedroom.id)
        #expect(queue?.currentItem != nil)
    }
}
