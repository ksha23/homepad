import Foundation
import HomePadCore

/// Encodes demo items in the shape Home Assistant's Music Assistant actions answer
/// with (`MEDIA_ITEM_SCHEMA`), so the demo runs through the same decoders.
extension MAMediaItem {
    var json: JSONValue {
        var fields: [String: JSONValue] = [
            "media_type": .string(mediaType.rawValue),
            "uri": .string(uri),
            "name": .string(name),
            "version": .string(version),
            "image": imageURL.map { .string($0.absoluteString) } ?? .null,
            "favorite": .bool(isFavorite),
            "explicit": .bool(isExplicit),
        ]
        if !artists.isEmpty {
            fields["artists"] = .array(artists.map { name in
                ["media_type": "artist", "uri": .string("library://artist/\(name)"), "name": .string(name),
                 "version": "", "image": .null]
            })
        }
        if let albumName {
            fields["album"] = ["media_type": "album", "uri": .string("library://album/\(albumName)"),
                               "name": .string(albumName), "version": "", "image": .null]
        }
        return .object(fields)
    }
}

extension DemoMusicCatalog.Track {
    /// A `QUEUE_ITEM_SCHEMA` entry for the demo `get_queue` answer.
    func queueJSON(id: String) -> JSONValue {
        [
            "queue_item_id": .string(id),
            "name": .string("\(artist) - \(title)"),
            "duration": .number(duration),
            "media_item": MAMediaItem(mediaType: .track, uri: "apple_music://track/\(id)", name: title,
                                      artists: [artist], albumName: album).json,
        ]
    }
}
