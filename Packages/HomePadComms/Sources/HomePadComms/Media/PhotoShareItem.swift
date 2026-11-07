import CommsKit
import CoreTransferable
import UniformTypeIdentifiers

/// A photo for the system share sheet. The original is fetched when the person picks a
/// destination, and it travels in memory, so nothing is written to disk to share it.
struct PhotoShareItem: Transferable {
    let attachment: CommsAttachment
    let load: @Sendable () async throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .image) { try await $0.load() }
    }
}

extension AttachmentLoader {
    /// Share items for photo attachments.
    @MainActor
    func shareItems(_ photos: [CommsAttachment]) -> [PhotoShareItem] {
        photos.map { photo in PhotoShareItem(attachment: photo) { [self] in try await original(photo.id) } }
    }
}
