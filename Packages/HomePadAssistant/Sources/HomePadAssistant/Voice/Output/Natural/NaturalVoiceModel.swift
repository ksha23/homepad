import CryptoKit
import Foundation
import Observation

/// The Kokoro-82M weights behind the Natural voice: downloaded once from Hugging Face
/// when someone picks that voice, checked against a known checksum, and kept in
/// Application Support. Nothing downloads while Apple voices are in use.
@MainActor
@Observable
final class NaturalVoiceModel {
    enum State: Equatable {
        case missing
        /// Fraction downloaded, 0 to 1.
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .missing
    let fileURL: URL
    /// Called once a download has finished and checked out.
    @ObservationIgnored var onReady: (() -> Void)?

    /// A pinned revision, so the file never changes under the checksum.
    nonisolated static let remoteURL = URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/a71e4d38b236d968966a2002c4c895dbd12b1c3c/kokoro-v1_0.safetensors")!
    nonisolated static let sha256 = "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"
    nonisolated static let byteCount: Int64 = 327_115_152

    @ObservationIgnored private var download: Task<Void, Never>?

    init(folder: URL? = nil) {
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voices", isDirectory: true)
        fileURL = base.appendingPathComponent("kokoro-v1_0.safetensors")
        if Self.looksComplete(fileURL) { state = .ready }
    }

    /// Starts the download unless the model is here or already coming.
    func downloadIfNeeded() {
        switch state {
        case .ready, .downloading: return
        case .missing, .failed: break
        }
        state = .downloading(0)
        download = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fetch()
                self.state = .ready
                self.onReady?()
            } catch {
                self.state = .failed("The natural voice could not be downloaded. \(error.localizedDescription)")
            }
            self.download = nil
        }
    }

    private func fetch() async throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent("kokoro-download.partial")
        try await ModelDownload.fetch(Self.remoteURL, to: staged) { [weak self] fraction in
            Task { @MainActor in
                if case .downloading = self?.state { self?.state = .downloading(fraction) }
            }
        }
        let digest = try await Task.detached(priority: .utility) { try Self.sha256Hex(of: staged) }.value
        guard digest == Self.sha256 else {
            try? FileManager.default.removeItem(at: staged)
            throw CocoaError(.fileReadCorruptFile)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        try FileManager.default.moveItem(at: staged, to: fileURL)
    }

    /// A quick check at launch: the full checksum ran when the file arrived.
    nonisolated static func looksComplete(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size == byteCount
    }

    /// The file's SHA-256, read in chunks so the 330 MB model never sits in memory.
    nonisolated static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One file download with progress, to a path of our choosing.
private enum ModelDownload {
    static func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = Delegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let progress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        private var moveError: Error?

        init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
            self.destination = destination
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : NaturalVoiceModel.byteCount
            progress(min(1, Double(totalBytesWritten) / Double(total)))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The temporary file is deleted when this returns, so it moves now.
            do {
                if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
                    throw URLError(.badServerResponse)
                }
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                moveError = error
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error ?? moveError {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume()
            }
            continuation = nil
        }
    }
}
