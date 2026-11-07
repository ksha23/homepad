import Foundation
import HomePadCore
import Observation
import UIKit

/// Plays an MJPEG URL: streams bytes, splits frames with `MJPEGParser`, decodes
/// the newest frame off the main thread and publishes it. Reconnects if the stream ends.
@MainActor
@Observable
final class MJPEGStream {
    private(set) var image: UIImage?
    private(set) var errorMessage: String?

    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var request: URLRequest?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private let maximumFramesPerSecond: Double

    init(maximumFramesPerSecond: Double = 15) {
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }

    func start(_ request: URLRequest) {
        stop()
        self.request = request
        connect()
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        request = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func connect() {
        guard let request else { return }
        let receiver = Receiver(minimumInterval: 1 / maximumFramesPerSecond) { [weak self] image in
            Task { @MainActor in
                self?.image = image
                self?.errorMessage = nil
            }
        } onFinish: { [weak self] message in
            Task { @MainActor in self?.streamEnded(message) }
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: queue)
        self.session = session
        session.dataTask(with: request).resume()
    }

    private func streamEnded(_ message: String?) {
        guard request != nil else { return }
        if let message { errorMessage = message }
        session?.finishTasksAndInvalidate()
        session = nil
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    /// Only touched on the session's serial delegate queue, which makes the mutable parser safe.
    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private var parser = MJPEGParser(contentType: nil)
        private var lastDelivery: TimeInterval = 0
        private let minimumInterval: TimeInterval
        private let onFrame: (UIImage) -> Void
        private let onFinish: (String?) -> Void

        init(minimumInterval: TimeInterval, onFrame: @escaping (UIImage) -> Void, onFinish: @escaping (String?) -> Void) {
            self.minimumInterval = minimumInterval
            self.onFrame = onFrame
            self.onFinish = onFinish
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            guard http.map({ (200..<300).contains($0.statusCode) }) ?? true else {
                completionHandler(.cancel)
                onFinish("The camera stream answered with status \(http?.statusCode ?? 0).")
                return
            }
            parser = MJPEGParser(contentType: http?.value(forHTTPHeaderField: "Content-Type"))
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let newest = parser.append(data).last else { return }
            let now = Date().timeIntervalSinceReferenceDate
            guard now - lastDelivery >= minimumInterval else { return }
            lastDelivery = now
            if let image = UIImage(data: newest)?.preparingForDisplay() {
                onFrame(image)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let cancelled = (error as? URLError)?.code == .cancelled
            if !cancelled { onFinish(error?.localizedDescription) }
        }
    }
}
