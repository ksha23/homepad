import Foundation
import HomePadCore
import Network

/// A tiny LAN HTTP server for the security camera, built on Network.framework.
///
/// - `GET /stream.mjpeg?token=...` streams frames as `multipart/x-mixed-replace`.
/// - `GET /snapshot.jpg?token=...` returns the latest frame.
///
/// Home Assistant's "MJPEG IP Camera" integration reads both URLs directly.
/// Everything runs on one serial queue. Callbacks hop to the main actor.
final class MJPEGServer: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case stopped
        case listening(port: UInt16)
        case failed(String)
    }

    /// Called on the main actor.
    var onStateChange: (@MainActor (State) -> Void)?
    /// Called on the main actor with the number of open streams.
    var onStreamCountChange: (@MainActor (Int) -> Void)?

    static let maximumClients = 6
    /// A snapshot older than this means the camera is paused.
    static let snapshotMaxAge: TimeInterval = 10

    private let queue = DispatchQueue(label: "cameralab.mjpeg")
    private let lock = NSLock()
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: MJPEGClient] = [:]
    private var token = ""
    private var latest: (jpeg: Data, at: Date)?
    private var streamCount = 0
    private let log = Log.make("CameraLab.MJPEG")

    /// True when at least one client is watching the stream. Safe from any thread.
    var hasViewers: Bool { lock.withLock { streamCount > 0 } }

    func start(port: UInt16, token: String) {
        queue.async { [self] in
            stopListener()
            self.token = token
            guard let endpointPort = NWEndpoint.Port(rawValue: port), port > 0 else {
                report(.failed("Port \(port) is not valid."))
                return
            }
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters, on: endpointPort)
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state, port: port) }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                report(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            stopListener()
            latest = nil
            report(.stopped)
        }
    }

    /// Changes the token and disconnects everyone who used the old one.
    func updateToken(_ token: String) {
        queue.async { [self] in
            self.token = token
            clients.values.forEach { $0.close() }
        }
    }

    /// Hands the newest JPEG to every stream and keeps it for snapshots.
    func publish(jpeg: Data) {
        queue.async { [self] in
            latest = (jpeg, Date())
            for client in clients.values where client.isStreaming {
                client.send(frame: jpeg)
            }
        }
    }

    // MARK: Connections (server queue)

    private func accept(_ connection: NWConnection) {
        guard clients.count < Self.maximumClients else {
            connection.start(queue: queue)
            let busy = MJPEGFraming.textResponse(status: .serviceUnavailable, message: "Too many viewers.")
            connection.send(content: busy, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let client = MJPEGClient(
            connection: connection, queue: queue,
            onRequest: { [weak self] client, outcome in self?.handle(outcome, from: client) },
            onClose: { [weak self] client in self?.remove(client) }
        )
        clients[ObjectIdentifier(client)] = client
        client.start()
    }

    private func handle(_ outcome: HTTPRequestParser.Outcome, from client: MJPEGClient) {
        guard case .complete(let request) = outcome else {
            client.respond(MJPEGFraming.textResponse(status: .badRequest, message: "Bad request."))
            return
        }
        switch MJPEGRoute.resolve(request, token: token) {
        case .stream(let headOnly):
            if headOnly {
                client.respond(MJPEGFraming.streamHeader())
                return
            }
            client.beginStream(header: MJPEGFraming.streamHeader())
            if let latest { client.send(frame: latest.jpeg) }
            updateStreamCount()
        case .snapshot(let headOnly):
            if let latest, Date().timeIntervalSince(latest.at) < Self.snapshotMaxAge {
                client.respond(MJPEGFraming.response(status: .ok, contentType: "image/jpeg", body: latest.jpeg, includeBody: !headOnly))
            } else {
                client.respond(MJPEGFraming.textResponse(status: .serviceUnavailable, message: "The camera is paused.",
                                                         extraHeaders: [("Retry-After", "30")]))
            }
        case .unauthorized:
            log.notice("Rejected a camera request with a missing or wrong token")
            client.respond(MJPEGFraming.textResponse(status: .unauthorized, message: "Missing or wrong token."))
        case .notFound:
            client.respond(MJPEGFraming.textResponse(status: .notFound, message: "Not found."))
        case .methodNotAllowed:
            client.respond(MJPEGFraming.textResponse(status: .methodNotAllowed, message: "Only GET and HEAD.",
                                                     extraHeaders: [("Allow", "GET, HEAD")]))
        }
    }

    private func remove(_ client: MJPEGClient) {
        clients[ObjectIdentifier(client)] = nil
        updateStreamCount()
    }

    private func updateStreamCount() {
        let count = clients.values.filter(\.isStreaming).count
        lock.withLock { streamCount = count }
        let callback = onStreamCountChange
        Task { @MainActor in callback?(count) }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        clients.values.forEach { $0.close() }
        clients.removeAll()
        updateStreamCount()
    }

    private func listenerChanged(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            log.info("Camera server listening on port \(port)")
            report(.listening(port: port))
        case .failed(let error):
            log.error("Camera server failed: \(error.localizedDescription, privacy: .public)")
            report(.failed(Self.describe(error, port: port)))
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    private func report(_ state: State) {
        let callback = onStateChange
        Task { @MainActor in callback?(state) }
    }

    private static func describe(_ error: NWError, port: UInt16) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use. Pick another port in Settings."
        }
        return error.localizedDescription
    }
}
