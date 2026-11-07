import CommsKit
import Foundation
import Observation

/// Downloads originals and saves them to Photos or Files. One per photo, stack or viewer,
/// so each shows its own progress and result.
@MainActor
@Observable
final class MediaSaver {
    /// Shown in an alert: a result or an error.
    var notice: String?
    var busy = false
    var exportFiles: [ExportFile] = []
    var isExporting = false

    func saveToPhotos(_ list: [CommsAttachment], loader: AttachmentLoader?) async {
        guard let loader, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            var items: [PhotoLibrarySaver.Item] = []
            for attachment in list {
                let data = try await loader.original(attachment.id)
                items.append(.init(data: data, filename: attachment.name, isVideo: attachment.mimeType.hasPrefix("video/")))
            }
            try await PhotoLibrarySaver.save(items)
            SavedMedia.shared.insert(list.map(\.id))
            notice = list.count == 1 ? "Saved to Photos." : "Saved \(list.count) items to Photos."
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Downloads the files, then opens the system "save to" sheet.
    func saveToFiles(_ list: [CommsAttachment], loader: AttachmentLoader?) async {
        guard let loader, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            var files: [ExportFile] = []
            for attachment in list {
                files.append(ExportFile(data: try await loader.original(attachment.id), filename: attachment.name))
            }
            exportFiles = files
            isExporting = true
        } catch {
            notice = error.localizedDescription
        }
    }

    /// The exporter is done with the bytes.
    func finishExport(_ result: Result<[URL], Error>) {
        exportFiles = []
        if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled { notice = error.localizedDescription }
    }
}
