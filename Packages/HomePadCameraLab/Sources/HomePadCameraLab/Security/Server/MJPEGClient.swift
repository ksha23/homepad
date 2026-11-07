import Foundation
import Network

/// One TCP connection to the camera server. Reads a request, then either
/// answers once and closes, or keeps streaming frames. Confined to the
/// server's queue.
final class MJPEGClient: @unchecked Sendable {
    let connection: NWConnection
    private(set) var isStreaming = false
    private var buffer = Data()
    private var isSending = false
    private var pendingFrame: Data?
    private var isClosed = false
    private let queue: DispatchQueue
    private let onRequest: (MJPEGClient, HTTPRequestParser.Outcome) -> Void
    private let onClose: (MJPEGClient) -> Void

    /// Seconds a client has to finish sending its request headers.
    static let requestTimeout: TimeInterval = 10

    init(connection: NWConnection, queue: DispatchQueue,
         onRequest: @escaping (MJPEGClient, HTTPRequestParser.Outcome) -> Void,
         onClose: @escaping (MJPEGClient) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onRequest = onRequest
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self] in
            guard let self, !self.isStreaming, !self.isClosed else { return }
            if case .incomplete = HTTPRequestParser.parse(self.buffer) { self.close() }
        }
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data { self.buffer.append(data) }
            let outcome = HTTPRequestParser.parse(self.buffer)
            if case .incomplete = outcome {
                if isComplete || error != nil { self.close() } else { self.receive() }
                return
            }
            self.onRequest(self, outcome)
        }
    }

    /// Sends a whole response, then closes.
    func respond(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    /// Sends the stream header and switches to streaming mode.
    func beginStream(header: Data) {
        isStreaming = true
        isSending = true
        connection.send(content: header, completion: .contentProcessed { [weak self] error in
            self?.didSend(error: error)
        })
    }

    /// Sends one frame. While a send is in flight only the newest frame waits,
    /// so slow clients get fewer frames instead of growing a backlog.
    func send(frame: Data) {
        guard isStreaming, !isClosed else { return }
        guard !isSending else {
            pendingFrame = frame
            return
        }
        isSending = true
        connection.send(content: MJPEGFraming.part(jpeg: frame), completion: .contentProcessed { [weak self] error in
            self?.didSend(error: error)
        })
    }

    private func didSend(error: NWError?) {
        isSending = false
        if error != nil {
            close()
        } else if let next = pendingFrame {
            pendingFrame = nil
            send(frame: next)
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        isStreaming = false
        connection.cancel()
        onClose(self)
    }
}
