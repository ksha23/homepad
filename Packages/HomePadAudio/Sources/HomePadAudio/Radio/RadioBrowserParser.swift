import Foundation

/// Turns Radio Browser API JSON (`/json/stations/...`) into `RadioStation`s.
///
/// The directory is community-edited, so the parser is forgiving: numbers may
/// arrive as strings, fields may be empty, and stations that failed their last
/// health check or have no usable http(s) stream are dropped.
enum RadioBrowserParser {
    static func stations(from data: Data) throws -> [RadioStation] {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        var seen = Set<String>()
        return entries.compactMap(station(from:)).filter { seen.insert($0.id).inserted }
    }

    static func station(from entry: Entry) -> RadioStation? {
        guard entry.lastcheckok ?? 1 == 1 else { return nil }
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let stream = webURL(entry.url_resolved) ?? webURL(entry.url) else { return nil }
        let tags = (entry.tags ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        let country = entry.countrycode?.trimmingCharacters(in: .whitespaces)
        let codec = entry.codec?.trimmingCharacters(in: .whitespaces)
        return RadioStation(
            id: "rb:\(entry.stationuuid)",
            name: name,
            streamURL: stream,
            artworkURL: webURL(entry.favicon),
            homepageURL: webURL(entry.homepage),
            tags: Array(tags.prefix(6)),
            countryCode: country?.isEmpty == false ? country : nil,
            codec: codec?.isEmpty == false ? codec : nil,
            bitrate: normalizedBitrate(entry.bitrate),
            origin: .radioBrowser
        )
    }

    /// Radio Browser reports kbps, but some HLS entries report bits per second.
    static func normalizedBitrate(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value >= 10_000 ? value / 1000 : value
    }

    private static func webURL(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty,
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// The subset of the Radio Browser station object HomePad reads.
    struct Entry: Decodable {
        var stationuuid: String
        var name: String
        var url: String?
        var url_resolved: String?
        var homepage: String?
        var favicon: String?
        var tags: String?
        var countrycode: String?
        var codec: String?
        var bitrate: Int?
        var lastcheckok: Int?

        enum CodingKeys: String, CodingKey {
            case stationuuid, name, url, url_resolved, homepage, favicon, tags, countrycode, codec, bitrate, lastcheckok
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stationuuid = try container.decode(String.self, forKey: .stationuuid)
            name = (try? container.decode(String.self, forKey: .name)) ?? ""
            url = try? container.decode(String.self, forKey: .url)
            url_resolved = try? container.decode(String.self, forKey: .url_resolved)
            homepage = try? container.decode(String.self, forKey: .homepage)
            favicon = try? container.decode(String.self, forKey: .favicon)
            tags = try? container.decode(String.self, forKey: .tags)
            countrycode = try? container.decode(String.self, forKey: .countrycode)
            codec = try? container.decode(String.self, forKey: .codec)
            bitrate = Self.lenientInt(container, .bitrate)
            lastcheckok = Self.lenientInt(container, .lastcheckok)
        }

        private static func lenientInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
            if let value = try? container.decode(Int.self, forKey: key) { return value }
            if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
            if let value = try? container.decode(Bool.self, forKey: key) { return value ? 1 : 0 }
            return nil
        }
    }
}
