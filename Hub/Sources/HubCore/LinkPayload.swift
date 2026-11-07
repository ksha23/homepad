import Foundation

/// A rich link's metadata, read from a message's `payload_data`.
/// That blob is an NSKeyedArchiver plist of Apple's LPLinkMetadata. It is read as plain
/// property-list data, following the archive's internal references by hand.
struct LinkPayload {
    var url: String?
    var title: String?
    /// Which of the message's attachments holds the preview picture.
    var imageIndex: Int?

    init?(data: Data) {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any],
              let top = plist["$top"] as? [String: Any],
              let root = Self.resolve(top["root"], objects) as? [String: Any],
              let metadata = Self.resolve(root["richLinkMetadata"], objects) as? [String: Any] else { return nil }
        url = Self.string(metadata["URL"], objects) ?? Self.string(metadata["originalURL"], objects)
        title = Self.string(metadata["title"], objects)
        if let image = Self.resolve(metadata["image"], objects) as? [String: Any],
           let index = Self.resolve(image["richLinkImageAttachmentSubstituteIndex"], objects) as? Int {
            imageIndex = index
        }
        if url == nil && title == nil { return nil }
    }

    /// Follows an archive reference (`CF$UID`) to the object it points at.
    private static func resolve(_ value: Any?, _ objects: [Any]) -> Any? {
        guard let value else { return nil }
        let text = String(describing: value)
        guard text.contains("CFKeyedArchiverUID"), let range = text.range(of: "value = ") else { return value }
        let digits = text[range.upperBound...].prefix(while: \.isNumber)
        guard let index = Int(digits), objects.indices.contains(index) else { return nil }
        return objects[index]
    }

    /// A string, or the `NS.relative` text of an archived URL.
    private static func string(_ value: Any?, _ objects: [Any]) -> String? {
        let object = resolve(value, objects)
        if let text = object as? String, text != "$null" { return text }
        if let dictionary = object as? [String: Any] { return string(dictionary["NS.relative"], objects) }
        return nil
    }
}
