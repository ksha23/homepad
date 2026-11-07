import CommsKit
import Foundation

extension HubClient {
    /// Uploads a file and has the hub send it into a conversation through Messages.
    /// Files over `CommsUpload.maxBytes` are refused here, before any bytes move.
    public func sendAttachment(_ data: Data, filename: String, mimeType: String, to conversationID: String) async throws {
        guard CommsUpload.allows(data.count) else { throw Failure.tooLarge }
        var upload = try request(CommsRoutes.sendAttachment(in: conversationID), method: "POST")
        upload.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let name = CommsUpload.sanitizedFilename(filename)
        upload.setValue(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name, forHTTPHeaderField: CommsUpload.filenameHeader)
        upload.timeoutInterval = 180
        do {
            let (_, response) = try await session.upload(for: upload, from: data)
            try Self.check(response)
        } catch {
            throw Self.wrap(error)
        }
    }

    /// The original file of an attachment, with progress from 0 to 1 while it downloads.
    /// The bytes come back in memory. The system's own download file is gone when this returns.
    public func downloadOriginal(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> Data {
        var download = try request(CommsRoutes.attachment(id))
        download.timeoutInterval = 60
        let handle = DownloadHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: download) { location, response, error in
                    handle.observation = nil
                    do {
                        if let error { throw error }
                        if let response { try Self.check(response) }
                        guard let location else { throw Failure.server(0) }
                        continuation.resume(returning: try Data(contentsOf: location))
                    } catch {
                        continuation.resume(throwing: Self.wrap(error))
                    }
                }
                handle.task = task
                handle.observation = task.progress.observe(\.fractionCompleted) { value, _ in progress(value.fractionCompleted) }
                task.resume()
            }
        } onCancel: {
            handle.task?.cancel()
        }
    }
}

/// Keeps a download task and its progress observer reachable from the cancel handler.
private final class DownloadHandle: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}
