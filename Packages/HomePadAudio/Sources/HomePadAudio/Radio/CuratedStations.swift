import Foundation

/// The built-in station list: listener-supported, commercial-free public streams
/// that work without an account. SomaFM, Radio Paradise and KEXP all publish
/// these URLs for third-party players.
enum CuratedStations {
    static let all: [RadioStation] = [
        soma("groovesalad", "Groove Salad", logo: "groovesalad512.png", ["ambient", "downtempo"]),
        soma("dronezone", "Drone Zone", logo: "dronezone512.png", ["ambient", "sleep"]),
        soma("deepspaceone", "Deep Space One", logo: "deepspaceone512.png", ["ambient", "space"]),
        soma("lush", "Lush", logo: "lush512.png", ["electronic", "vocal"]),
        soma("secretagent", "Secret Agent", logo: "secretagent512.png", ["lounge", "spy jazz"]),
        soma("bossa", "Bossa Beyond", logo: "bossa-512.jpg", ["bossa nova", "world"]),
        soma("indiepop", "Indie Pop Rocks!", logo: "indiepop512.png", ["indie", "pop"]),
        soma("seventies", "Left Coast 70s", logo: "seventies512.jpg", ["70s", "rock"]),
        soma("bootliquor", "Boot Liquor", logo: "bootliquor512.png", ["americana", "country"]),
        soma("fluid", "Fluid", logo: "fluid512.jpg", ["instrumental", "hip hop"]),
        station("radioparadise:main", "Radio Paradise", "https://stream.radioparadise.com/aac-320",
                artwork: "https://radioparadise.com/apple-touch-icon.png", tags: ["eclectic", "rock"]),
        station("radioparadise:mellow", "Radio Paradise Mellow", "https://stream.radioparadise.com/mellow-320",
                artwork: "https://radioparadise.com/apple-touch-icon.png", tags: ["mellow", "eclectic"]),
        station("kexp", "KEXP Seattle", "https://kexp.streamguys1.com/kexp160.aac",
                artwork: nil, tags: ["indie", "live"]),
    ]

    static let defaultFavoriteIDs = ["soma:groovesalad", "radioparadise:main", "kexp", "soma:dronezone"]

    private static func soma(_ channel: String, _ name: String, logo: String, _ tags: [String]) -> RadioStation {
        RadioStation(
            id: "soma:\(channel)", name: "SomaFM \(name)",
            streamURL: URL(string: "https://ice1.somafm.com/\(channel)-128-mp3")!,
            artworkURL: URL(string: "https://api.somafm.com/logos/512/\(logo)"),
            homepageURL: URL(string: "https://somafm.com/\(channel)/"),
            tags: tags, countryCode: "US", codec: "MP3", bitrate: 128, origin: .curated
        )
    }

    private static func station(_ id: String, _ name: String, _ url: String, artwork: String?, tags: [String]) -> RadioStation {
        RadioStation(
            id: id, name: name, streamURL: URL(string: url)!, artworkURL: artwork.flatMap(URL.init(string:)),
            tags: tags, countryCode: "US", codec: "AAC", origin: .curated
        )
    }
}
