import CommsKit
import Foundation
import Observation
import PhotosUI
import SwiftUI

/// Sends photos and videos chosen in the composer, one after another so they arrive in order.
/// The bytes stay in memory, and the hub deletes its copy once Messages has the file.
@MainActor
@Observable
final class PhotoUploads {
    private(set) var sending = 0
    var failure: String?

    func send(_ items: [PhotosPickerItem], to conversationID: String, store: CommsStore) async {
        sending += items.count
        defer { sending = 0 }
        for (index, item) in items.enumerated() {
            let type = item.supportedContentTypes.first
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
                try await store.sendAttachment(
                    data, filename: PickedMedia.filename(for: type, index: index), mimeType: PickedMedia.mimeType(for: type), to: conversationID
                )
            } catch {
                failure = error.localizedDescription
                return
            }
            sending -= 1
        }
    }
}
