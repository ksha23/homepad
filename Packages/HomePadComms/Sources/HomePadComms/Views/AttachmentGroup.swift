import CommsKit
import Foundation

/// The pieces of a message's attachments as they are drawn: all photos together
/// (one photo, or a stack), then each video and file on its own.
enum AttachmentGroup: Identifiable {
    case photos([CommsAttachment])
    case video(CommsAttachment)
    case file(CommsAttachment)

    var id: String {
        switch self {
        case .photos(let list): "photos-" + (list.first?.id ?? "")
        case .video(let item), .file(let item): item.id
        }
    }

    static func make(_ attachments: [CommsAttachment]) -> [AttachmentGroup] {
        let photos = attachments.filter { $0.mimeType.hasPrefix("image/") }
        var groups: [AttachmentGroup] = photos.isEmpty ? [] : [.photos(photos)]
        for item in attachments where !item.mimeType.hasPrefix("image/") {
            groups.append(item.mimeType.hasPrefix("video/") ? .video(item) : .file(item))
        }
        return groups
    }
}
