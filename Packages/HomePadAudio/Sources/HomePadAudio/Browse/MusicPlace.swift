import Foundation
import HomePadCore
import Observation

/// Where the Music app was left, so it opens there again: the section, the
/// Library's kind and the album, playlist or artist page on top. Scroll
/// positions are not kept. Everything is saved here, on this iPad, in plain
/// settings keys, so moving to a shared state API later changes only this type.
///
/// The debug launch arguments win. `-HomePadMusicSection` and
/// `-HomePadMusicLibrary` choose what they name, and `-HomePadMusicPage` opens
/// its page. A launch with any of them shows no saved page and saves nothing,
/// so screenshots and UI tests never move where the person left Music.
@MainActor
@Observable
final class MusicPlace {
    static let sectionKey = SettingKey<String>("audio.music.place.section", default: MusicSection.listenNow.rawValue)
    static let libraryKindKey = SettingKey<String>("audio.music.place.libraryKind", default: LibraryKind.playlists.rawValue)
    /// The page on top, by its source, kind and ID, the way Recently Played keeps items.
    static let pageKey = SettingKey<RecentMusicItem?>("audio.music.place.page", default: nil)

    var section: MusicSection {
        didSet { save(Self.sectionKey, section.rawValue) }
    }

    var libraryKind: LibraryKind {
        didSet { save(Self.libraryKindKey, libraryKind.rawValue) }
    }

    @ObservationIgnored private let settings: SettingsStore
    /// True when launch arguments choose the place.
    @ObservationIgnored private let isPinned: Bool
    @ObservationIgnored private var hasReopenedPage = false

    /// - Parameter launchArguments: Where the debug launch arguments are read (tests pass their own).
    init(settings: SettingsStore, launchArguments: UserDefaults = .standard) {
        self.settings = settings
        let launchSection = launchArguments.string(forKey: "HomePadMusicSection").flatMap(MusicSection.init(rawValue:))
        let launchKind = launchArguments.string(forKey: "HomePadMusicLibrary").flatMap(LibraryKind.init(rawValue:))
        isPinned = launchSection != nil || launchKind != nil || launchArguments.string(forKey: "HomePadMusicPage") != nil
        section = launchSection ?? MusicSection(rawValue: settings[Self.sectionKey]) ?? .listenNow
        libraryKind = launchKind ?? LibraryKind(rawValue: settings[Self.libraryKindKey]) ?? .playlists
    }

    /// Saves the page on top of the Music app's stack, or that none is open.
    func save(page: MusicPage?) {
        guard !isPinned else { return }
        settings[Self.pageKey] = page?.savedReference
    }

    /// The page to open again the first time Music opens after a launch. Nil
    /// after that, when no page was open, or when launch arguments choose the place.
    func pageToReopen() -> RecentMusicItem? {
        guard !hasReopenedPage else { return nil }
        hasReopenedPage = true
        return isPinned ? nil : settings[Self.pageKey]
    }

    private func save(_ key: SettingKey<String>, _ value: String) {
        guard !isPinned else { return }
        settings[key] = value
    }
}

extension MusicPage {
    /// The page by its source, kind and ID, which `openRecent` looks up again.
    var savedReference: RecentMusicItem? {
        switch self {
        case .appleMusicAlbum(let album):
            RecentMusicItem(source: .appleMusic, kind: .album, itemID: album.id.rawValue, title: album.title)
        case .appleMusicPlaylist(let playlist):
            RecentMusicItem(source: .appleMusic, kind: .playlist, itemID: playlist.id.rawValue, title: playlist.name)
        case .appleMusicArtist(let artist):
            RecentMusicItem(source: .appleMusic, kind: .artist, itemID: artist.id.rawValue, title: artist.name)
        case .demo(let item):
            Self.demoKind(item.mediaType).map { RecentMusicItem(source: .demo, kind: $0, itemID: item.name, title: item.name) }
        case .spotify(let item):
            item.recent
        case .memberPlaylist:
            // A person's own playlist shows only while they are recognized, so it is not reopened after a restart.
            nil
        }
    }

    private static func demoKind(_ type: MAMediaItem.MediaType) -> RecentMusicItem.Kind? {
        switch type {
        case .album: .album
        case .playlist: .playlist
        case .artist: .artist
        default: nil
        }
    }
}

extension AudioMediaService {
    /// Called as the Music app opens. `-HomePadMusicPage` opens its demo page.
    /// Otherwise the pages left open are still there, and the first time after
    /// a launch the page saved last time comes back, looked up from its source.
    func reopenMusicPage() {
        if MusicPageLaunch.open(in: self) { return }
        guard let saved = musicPlace.pageToReopen(), pages.pages.isEmpty else { return }
        Task { await openRecent(saved) }
    }
}
