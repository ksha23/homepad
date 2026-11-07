import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

@Suite struct RadioBrowserParsingTests {
    @Test func parsesHealthyStationsAndDropsBrokenOnes() throws {
        let stations = try RadioBrowserParser.stations(from: RadioFixtures.search)
        #expect(stations.map(\.id) == ["rb:960cf833-0601-11e8-ae97-52543be04c81", "rb:608bc971-3ec5-4c05-8143-de96c3bdb030"])

        let groove = stations[0]
        #expect(groove.name == "SomaFM Groove Salad (128k MP3)")
        #expect(groove.streamURL.absoluteString == "https://ice5.somafm.com/groovesalad-128-mp3")
        #expect(groove.artworkURL?.absoluteString == "https://somafm.com/img3/groovesalad-400.jpg")
        #expect(groove.homepageURL?.host() == "somafm.com")
        #expect(groove.tags == ["ambient", "chillout", "downtempo", "groove", "lounge", "sleep"])
        #expect(groove.countryCode == "US")
        #expect(groove.codec == "MP3")
        #expect(groove.bitrate == 128)
        #expect(groove.origin == .radioBrowser)
        #expect(groove.subtitle == "Ambient, Chillout")
    }

    @Test func fallsBackToURLAndNormalizesFields() throws {
        let hls = try RadioBrowserParser.stations(from: RadioFixtures.search)[1]
        #expect(hls.streamURL.absoluteString == "https://hls.somafm.com/hls/groovesalad/320k/program.m3u8")
        #expect(hls.artworkURL == nil)
        #expect(hls.countryCode == nil)
        #expect(hls.tags == ["groove", "hls", "somafm"])
        #expect(hls.bitrate == 320)
    }

    @Test func toleratesStringNumbersAndDuplicates() throws {
        let stations = try RadioBrowserParser.stations(from: RadioFixtures.duplicates)
        #expect(stations.count == 1)
        #expect(stations[0].bitrate == 160)
        #expect(stations[0].name == "KEXP 90.3")
    }

    @Test func rejectsNonArrayJSON() {
        #expect(throws: (any Error).self) { try RadioBrowserParser.stations(from: Data("{\"error\":1}".utf8)) }
        #expect(throws: Never.self) { try RadioBrowserParser.stations(from: Data("[]".utf8)) }
    }

    @Test func normalizesBitrate() {
        #expect(RadioBrowserParser.normalizedBitrate(nil) == nil)
        #expect(RadioBrowserParser.normalizedBitrate(0) == nil)
        #expect(RadioBrowserParser.normalizedBitrate(192) == 192)
        #expect(RadioBrowserParser.normalizedBitrate(128_000) == 128)
    }

    @Test func buildsSearchQueries() {
        let items = RadioBrowserClient.searchItems(name: "jazz", limit: 30)
        let dictionary = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dictionary == ["limit": "30", "hidebroken": "true", "order": "clickcount", "reverse": "true", "name": "jazz"])
        let tagItems = RadioBrowserClient.searchItems(tag: "LoFi", limit: 5)
        #expect(tagItems.contains(URLQueryItem(name: "tag", value: "lofi")))
        #expect(!tagItems.contains { $0.name == "name" })
    }

    @Test func mergesNameAndTagResults() throws {
        let stations = try RadioBrowserParser.stations(from: RadioFixtures.search)
        let merged = RadioBrowserClient.merge([stations[0]], [stations[0], stations[1]], limit: 10)
        #expect(merged.map(\.id) == stations.map(\.id))
        #expect(RadioBrowserClient.merge(stations, stations, limit: 1).count == 1)
    }
}

@Suite struct StreamParsingTests {
    @Test func splitsStreamTitles() {
        let song = StreamParsing.songInfo(fromStreamTitle: "Khruangbin - Maria También")
        #expect(song?.title == "Maria También")
        #expect(song?.artist == "Khruangbin")
        let id = StreamParsing.songInfo(fromStreamTitle: "  Station ID  ")
        #expect(id?.title == "Station ID")
        #expect(id?.artist == nil)
        let dashes = StreamParsing.songInfo(fromStreamTitle: "A - B - C")
        #expect(dashes?.title == "B - C")
        #expect(dashes?.artist == "A")
        #expect(StreamParsing.songInfo(fromStreamTitle: "") == nil)
        #expect(StreamParsing.songInfo(fromStreamTitle: " - ") == nil)
    }

    @Test func readsPLSAndM3UPlaylists() {
        let pls = """
        [playlist]
        numberofentries=2
        File1=https://ice1.somafm.com/groovesalad-128-mp3
        Title1=SomaFM: Groove Salad
        File2=https://ice2.somafm.com/groovesalad-128-mp3
        """
        #expect(StreamParsing.firstStreamURL(inPlaylist: pls)?.absoluteString == "https://ice1.somafm.com/groovesalad-128-mp3")
        let m3u = "#EXTM3U\n#EXTINF:-1,KEXP\nhttps://kexp.streamguys1.com/kexp160.aac\n"
        #expect(StreamParsing.firstStreamURL(inPlaylist: m3u)?.absoluteString == "https://kexp.streamguys1.com/kexp160.aac")
        #expect(StreamParsing.firstStreamURL(inPlaylist: "#EXTM3U\n#EXT-X-VERSION:3\nchunk.aac") == nil)
        #expect(StreamParsing.isPlaylistURL(URL(string: "https://somafm.com/groovesalad.pls")!))
        #expect(!StreamParsing.isPlaylistURL(URL(string: "https://hls.somafm.com/program.m3u8")!))
    }
}

@Suite struct RadioLibraryTests {
    @Test func matchesSpokenRequests() {
        let stations = CuratedStations.all
        #expect(RadioLibrary.match("groove salad", in: stations)?.id == "soma:groovesalad")
        #expect(RadioLibrary.match("Radio Paradise", in: stations)?.id == "radioparadise:main")
        #expect(RadioLibrary.match("kexp", in: stations)?.id == "kexp")
        #expect(RadioLibrary.match("some 70s rock", in: stations)?.id == "soma:seventies")
        #expect(RadioLibrary.match("polka", in: stations) == nil)
        #expect(RadioLibrary.match("radio", in: stations) == nil)
    }

    @Test func curatedStationsAreValid() {
        let ids = CuratedStations.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CuratedStations.defaultFavoriteIDs.allSatisfy { ids.contains($0) })
        #expect(CuratedStations.all.allSatisfy { $0.streamURL.scheme == "https" })
    }

    @MainActor @Test func addsCustomStationsAsFavorites() throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.test.\(UUID())")!)
        let library = RadioLibrary(settings: settings)
        let station = try library.addCustom(name: "My Stream", urlString: " https://example.com/live.mp3 ")
        #expect(library.isFavorite(station))
        #expect(library.favorites.last?.name == "My Stream")
        #expect(throws: AudioError.invalidStreamURL) { try library.addCustom(name: "Bad", urlString: "ftp://nope") }
        library.remove(station)
        #expect(!library.isFavorite(station))
        #expect(library.saved.isEmpty)
    }
}
