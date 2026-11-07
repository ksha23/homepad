import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Each household member's queue and place come back when HomePad recognizes
/// them, paused, and guests share the household's.
@MainActor @Suite struct MemberQueueTests {
    private let ana = HouseholdMember(name: "Ana")
    private let ben = HouseholdMember(name: "Ben")

    private func makeMedia(_ prepare: (SettingsStore) -> Void = { _ in }) -> (AudioMediaService, AppServices) {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.members.\(UUID())")!)
        prepare(settings)
        let services = AppServices(settings: settings)
        services.household.add(ana)
        services.household.add(ben)
        return (AudioMediaService(services: services, isDemo: false), services)
    }

    private func state(_ title: String, next: [String] = [], shuffle: Bool = false) -> MemberMusicState {
        var state = MemberMusicState()
        state.resume = MemberMusicStateTests.point(title)
        state.upNext = next.map { SavedQueueItem(id: $0, title: $0) }
        state.shuffle = shuffle
        return state
    }

    @Test func recognizedMemberGetsTheirOwnPlacePaused() {
        let (media, services) = makeMedia { settings in
            settings[MusicQueueOwner.member(ana.id).stateKey] = state("Ana's Song", next: ["Ana Next"], shuffle: true)
            settings[MusicQueueOwner.member(ben.id).stateKey] = state("Ben's Song", next: ["Ben Next 1", "Ben Next 2"])
        }
        services.household.recognize(ana.id)
        media.memberDidChange(to: ana.id)
        #expect(media.queueOwner == .member(ana.id))
        #expect(media.activeKind == .appleMusic)
        #expect(media.appleMusic.nowPlaying?.title == "Ana's Song")
        #expect(media.appleMusic.nowPlaying?.isPlaying == false)
        #expect(media.appleMusic.upNext.map(\.title) == ["Ana Next"])
        #expect(media.appleMusic.shuffle)

        services.household.recognize(ben.id)
        media.memberDidChange(to: ben.id)
        #expect(media.queueOwner == .member(ben.id))
        #expect(media.appleMusic.nowPlaying?.title == "Ben's Song")
        #expect(media.appleMusic.nowPlaying?.isPlaying == false)
        #expect(media.appleMusic.upNext.map(\.title) == ["Ben Next 1", "Ben Next 2"])
        #expect(!media.appleMusic.shuffle)
        // The saved place is also where a restart continues.
        #expect(services.settings[AudioSettings.appleMusicResume]?.title == "Ben's Song")
        #expect(services.settings[AudioSettings.musicQueueOwner] == ben.id.uuidString)
        withExtendedLifetime(services) {}
    }

    @Test func switchingSavesThePreviousOwnersPlaceFirst() {
        let (media, services) = makeMedia { settings in
            settings[MusicQueueOwner.member(ana.id).stateKey] = state("Ana's Song")
        }
        media.memberDidChange(to: ana.id)
        media.appleMusic.setRepeat(.all)
        media.memberDidChange(to: ben.id)
        let saved = services.settings[MusicQueueOwner.member(ana.id).stateKey]
        #expect(saved?.resume?.title == "Ana's Song")
        #expect(saved?.repeatMode == .all)
        // Ben has nothing saved: Now Playing is empty, not Ana's song.
        #expect(media.activeKind == nil)
        #expect(media.appleMusic.nowPlaying == nil)
        withExtendedLifetime(services) {}
    }

    @Test func guestsGetTheHouseholdQueue() {
        let (media, services) = makeMedia { settings in
            settings[MusicQueueOwner.household.stateKey] = state("House Song")
            settings[MusicQueueOwner.member(ana.id).stateKey] = state("Ana's Song")
        }
        media.memberDidChange(to: ana.id)
        media.memberDidChange(to: nil)
        #expect(media.queueOwner == .household)
        #expect(media.appleMusic.nowPlaying?.title == "House Song")
        withExtendedLifetime(services) {}
    }

    @Test func theSameOwnerAgainChangesNothing() {
        let (media, services) = makeMedia { settings in
            settings[MusicQueueOwner.member(ana.id).stateKey] = state("Ana's Song")
        }
        media.memberDidChange(to: ana.id)
        media.appleMusic.savedUpNext = []
        media.memberDidChange(to: ana.id)
        #expect(media.appleMusic.savedUpNext.isEmpty)
        withExtendedLifetime(services) {}
    }

    /// Radio, sleep sounds and the synced library stay as they are.
    @Test func otherSourcesStayAsTheyAre() {
        let (media, services) = makeMedia { settings in
            settings[MusicQueueOwner.member(ben.id).stateKey] = state("Ben's Song")
        }
        media.activeKind = .radio
        media.memberDidChange(to: ben.id)
        #expect(media.queueOwner == .household)
        #expect(media.activeKind == .radio)
        withExtendedLifetime(services) {}
    }

    /// After a restart the player's queue is filed under the person it belonged to.
    @Test func launchReadsTheOwnerAndTheirSavedUpNext() {
        let (media, services) = makeMedia { settings in
            settings[AudioSettings.musicQueueOwner] = ana.id.uuidString
            settings[MusicQueueOwner.member(ana.id).stateKey] = state("Ana's Song", next: ["Later"])
        }
        #expect(media.queueOwner == .member(ana.id))
        #expect(media.appleMusic.upNext.map(\.title) == ["Later"])
        // The iPad had no saved place of its own, so the owner's is shown.
        #expect(media.appleMusic.nowPlaying?.title == "Ana's Song")
        withExtendedLifetime(services) {}
    }

    @Test func newMusicBelongsToWhoeverStartsIt() {
        let (media, services) = makeMedia()
        services.household.recognize(ana.id)
        media.claimQueueForActiveMember()
        #expect(media.queueOwner == .member(ana.id))
        #expect(services.settings[AudioSettings.musicQueueOwner] == ana.id.uuidString)
        withExtendedLifetime(services) {}
    }

    @Test func recentlyPlayedIsPerPerson() {
        let (media, services) = makeMedia()
        services.household.recognize(ana.id)
        media.noteRecent(RecentMusicItem(source: .demo, kind: .album, itemID: "Night Signals", title: "Night Signals"))
        #expect(media.memberRecents.map(\.title) == ["Night Signals"])
        services.household.recognize(ben.id)
        #expect(media.memberRecents.isEmpty)
        services.household.signOut()
        media.noteRecent(RecentMusicItem(source: .demo, kind: .album, itemID: "Low Tide", title: "Low Tide"))
        #expect(media.memberRecents.map(\.title) == ["Low Tide"])
        services.household.recognize(ana.id)
        #expect(media.memberRecents.map(\.title) == ["Night Signals"])
        withExtendedLifetime(services) {}
    }
}
