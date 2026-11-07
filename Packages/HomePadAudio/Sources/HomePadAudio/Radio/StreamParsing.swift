import Foundation

/// Small pure parsers for internet radio.
enum StreamParsing {
    /// Splits Shoutcast or Icecast "StreamTitle" text such as "Artist - Title".
    /// Returns nil for empty titles and station IDs that carry no song.
    static func songInfo(fromStreamTitle raw: String) -> (title: String, artist: String?)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "-" else { return nil }
        if let range = text.range(of: " - ") {
            let artist = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let title = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return (title, artist.isEmpty ? nil : artist) }
        }
        return (text, nil)
    }

    /// Finds the first stream in a .pls or .m3u playlist body.
    /// HLS playlists (.m3u8 with #EXT-X tags) are left alone because AVPlayer plays them directly.
    static func firstStreamURL(inPlaylist body: String) -> URL? {
        let lines = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains(where: { $0.hasPrefix("#EXT-X-") }) { return nil }
        for line in lines {
            var candidate = line
            if line.lowercased().hasPrefix("file"), let equals = line.firstIndex(of: "=") {
                candidate = String(line[line.index(after: equals)...])
            } else if line.hasPrefix("#") || line.hasPrefix("[") || line.contains("=") {
                continue
            }
            if let url = URL(string: candidate), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url
            }
        }
        return nil
    }

    /// True when a URL names a playlist file rather than an audio stream.
    static func isPlaylistURL(_ url: URL) -> Bool {
        ["pls", "m3u"].contains(url.pathExtension.lowercased())
    }
}
