import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Decoding Music Assistant's action responses in the shapes Home Assistant documents.
@Suite struct MusicAssistantModelTests {
    @Test func searchResultsDecodeEveryList() throws {
        let results = MASearchResults(json: Fixture.response("ws_result_ma_search"))
        #expect(results.artists.map(\.name) == ["Taylor Swift"])
        #expect(results.albums.first?.artists == ["Taylor Swift"])
        #expect(results.tracks.count == 2)
        #expect(results.playlists.first?.provider == "spotify")
        #expect(results.podcasts.count == 1)
        #expect(results.radio.isEmpty)
        let track = try #require(results.tracks.first)
        #expect(track.mediaType == .track)
        #expect(track.albumName == "Midnights")
        #expect(track.subtitle == "Taylor Swift")
        #expect(results.tracks[1].displayName == "Shake It Off (Taylor's Version)")
        #expect(results.artists.first?.imageURL?.host() == "homeassistant.local")
    }

    @Test func bestMatchPrefersExactArtistThenKindWords() {
        let results = MASearchResults(json: Fixture.response("ws_result_ma_search"))
        #expect(results.bestMatch(for: "Taylor Swift")?.mediaType == .artist)
        #expect(results.bestMatch(for: "taylor swift playlist")?.name == "This Is Taylor Swift")
        #expect(results.bestMatch(for: "midnights album")?.name == "Midnights")
        #expect(results.bestMatch(for: "anti hero")?.name == "Anti-Hero")
        #expect(results.bestMatch(for: "anything", preferring: .album)?.name == "Midnights")
        #expect(MASearchResults().bestMatch(for: "x") == nil)
    }

    @Test func libraryItemsSkipMalformedEntries() {
        let items = MAMediaItem.list(Fixture.response("ws_result_ma_get_library_playlists")["items"])
        #expect(items.map(\.name) == ["Dinner Party", "Night Rider"])
        #expect(items[0].isFavorite)
        #expect(items[0].providerName == "Library")
        #expect(items[1].imageURL != nil)
    }

    @Test func queueIsReadByEntity() throws {
        let queue = try #require(MAQueue(response: Fixture.response("ws_result_ma_get_queue"), entityID: "media_player.kitchen"))
        #expect(queue.name == "Kitchen")
        #expect(queue.remainingCount == 8)
        #expect(queue.repeatMode == "all")
        #expect(queue.currentItem?.title == "Anti-Hero")
        #expect(queue.currentItem?.subtitle == "Taylor Swift")
        #expect(queue.nextItem?.title == "Khruangbin - August 10", "radio streams report their current song")
        #expect(MAQueue(response: [:], entityID: "media_player.kitchen") == nil)
    }

    @Test func playersComeFromTheMusicAssistantIntegrationOnly() {
        let sonos = HomeAccessory(id: "ha:media_player.sonos", name: "Sonos", kind: .mediaPlayer, backend: .homeAssistant,
                                  integration: "sonos")
        #expect(MusicAssistantPlayer(accessory: sonos) == nil)
        #expect(MusicAssistantPlayer(accessory: Speakers.display) == nil, "dashboard displays cannot play music")
        let kitchen = MusicAssistantPlayer(accessory: Speakers.kitchen)
        #expect(kitchen?.entityID == "media_player.kitchen")
        #expect(kitchen?.model == .homePodMini)
        #expect(MusicAssistantPlayer(accessory: Speakers.office)?.model == .sonos)
    }

    @Test func groupRolesFollowGroupMembers() throws {
        let leader = try #require(MusicAssistantPlayer(accessory: Speakers.player(
            "living_room", "Living Room", group: ["ha:media_player.living_room", "ha:media_player.kitchen"])))
        let follower = try #require(MusicAssistantPlayer(accessory: Speakers.player(
            "kitchen", "Kitchen", group: ["ha:media_player.living_room", "ha:media_player.kitchen"])))
        let groupPlayer = try #require(MusicAssistantPlayer(accessory: Speakers.player(
            "downstairs", "Downstairs", group: ["ha:media_player.living_room", "ha:media_player.kitchen"])))
        #expect(leader.leadsGroup && !leader.followsGroup)
        #expect(follower.followsGroup && !follower.leadsGroup)
        #expect(groupPlayer.isGroupPlayer)
        #expect(groupPlayer.model == .group)
    }
}

/// The `music_assistant.*` payloads, field by field.
@Suite struct MusicAssistantActionTests {
    @Test func searchCarriesTheConfigEntry() {
        let action = MusicAssistantAction.search(entryID: "01J", query: "Taylor Swift", mediaTypes: [.artist, .track], limit: 5)
        #expect(action.service == "search")
        #expect(action.returnsResponse)
        #expect(action.target == nil)
        #expect(action.data == [
            "config_entry_id": "01J", "name": "Taylor Swift", "limit": 5, "library_only": false,
            "media_type": ["artist", "track"],
        ])
    }

    @Test func libraryOrdersAndFilters() {
        let action = MusicAssistantAction.library(entryID: "01J", mediaType: .playlist, favorite: true, orderBy: "last_played_desc")
        #expect(action.service == "get_library")
        #expect(action.data == [
            "config_entry_id": "01J", "media_type": "playlist", "limit": 25, "offset": 0,
            "favorite": true, "order_by": "last_played_desc",
        ])
    }

    @Test func playMediaTargetsTheSpeaker() {
        let action = MusicAssistantAction.playMedia(entityID: "media_player.kitchen", mediaIDs: ["apple_music://track/1"],
                                                    mediaType: .track, enqueue: .next)
        #expect(action.service == "play_media")
        #expect(!action.returnsResponse)
        #expect(action.target == ["entity_id": "media_player.kitchen"])
        #expect(action.data == ["media_id": ["apple_music://track/1"], "media_type": "track", "enqueue": "next"])
        #expect(action.serviceData["entity_id"] == "media_player.kitchen")
        let untyped = MusicAssistantAction.playMedia(entityID: "media_player.kitchen", mediaIDs: ["jazz"], mediaType: .unknown)
        #expect(untyped.data["media_type"] == nil)
    }

    @Test func queueAndTransfer() {
        #expect(MusicAssistantAction.getQueue(entityID: "media_player.kitchen").returnsResponse)
        let transfer = MusicAssistantAction.transferQueue(to: "media_player.office", from: "media_player.kitchen")
        #expect(transfer.service == "transfer_queue")
        #expect(transfer.data == ["source_player": "media_player.kitchen", "auto_play": true])
        #expect(transfer.target == ["entity_id": "media_player.office"])
    }
}
