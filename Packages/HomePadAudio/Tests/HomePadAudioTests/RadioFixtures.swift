import Foundation

/// Radio Browser API responses, trimmed from real `/json/stations/search` output.
enum RadioFixtures {
    /// Four entries: a healthy MP3 station, an HLS station reporting bits per second,
    /// a station that failed its last check, and one with no usable stream URL.
    static let search = Data("""
    [
      {
        "changeuuid": "c4bf93a3-5bfc-4e63-b4c3-64268dd0e9b6",
        "stationuuid": "960cf833-0601-11e8-ae97-52543be04c81",
        "serveruuid": null,
        "name": "  SomaFM Groove Salad (128k MP3) ",
        "url": "https://somafm.com/groovesalad.pls",
        "url_resolved": "https://ice5.somafm.com/groovesalad-128-mp3",
        "homepage": "https://somafm.com/groovesalad/",
        "favicon": "https://somafm.com/img3/groovesalad-400.jpg",
        "tags": "ambient,chillout,downtempo,groove,lounge,sleep,electronic",
        "country": "The United States Of America",
        "countrycode": "US",
        "codec": "MP3",
        "bitrate": 128,
        "hls": 0,
        "lastcheckok": 1,
        "clickcount": 180,
        "geo_lat": 37.809784,
        "has_extended_info": false
      },
      {
        "changeuuid": "e29f280a-644f-4030-b1fa-893fc46d1d92",
        "stationuuid": "608bc971-3ec5-4c05-8143-de96c3bdb030",
        "name": "Soma FM Groove Salad 320K AAC HLS",
        "url": "https://hls.somafm.com/hls/groovesalad/320k/program.m3u8",
        "url_resolved": "",
        "homepage": "https://www.somafm.com/",
        "favicon": "",
        "tags": "groove, HLS ,somafm",
        "countrycode": "",
        "codec": "MP4",
        "bitrate": 320000,
        "hls": 1,
        "lastcheckok": 1
      },
      {
        "stationuuid": "11111111-2222-3333-4444-555555555555",
        "name": "Broken Jazz FM",
        "url": "http://example.invalid/jazz",
        "url_resolved": "http://example.invalid/jazz",
        "favicon": "http://example.invalid/logo.png",
        "tags": "jazz",
        "countrycode": "DE",
        "codec": "MP3",
        "bitrate": 64,
        "lastcheckok": 0
      },
      {
        "stationuuid": "66666666-7777-8888-9999-000000000000",
        "name": "No Stream Radio",
        "url": "rtsp://example.invalid/stream",
        "url_resolved": null,
        "favicon": null,
        "tags": null,
        "countrycode": "FR",
        "codec": "AAC",
        "bitrate": "96",
        "lastcheckok": "1"
      }
    ]
    """.utf8)

    /// Same station twice (the API can return duplicates across mirrors), numbers as strings.
    static let duplicates = Data("""
    [
      {"stationuuid": "aaaa", "name": "KEXP 90.3", "url_resolved": "https://kexp.streamguys1.com/kexp160.aac",
       "tags": "indie,live", "countrycode": "US", "codec": "AAC", "bitrate": "160", "lastcheckok": "1"},
      {"stationuuid": "aaaa", "name": "KEXP 90.3", "url_resolved": "https://kexp.streamguys1.com/kexp160.aac",
       "tags": "indie,live", "countrycode": "US", "codec": "AAC", "bitrate": 160, "lastcheckok": 1}
    ]
    """.utf8)
}
