import Foundation
import HomePadCore
import Observation

/// On a companion: the latest status of each HomePad, and a way to control them.
@MainActor
@Observable
public final class RemoteHomePads {
    public private(set) var statuses: [String: HomePadStatus] = [:]

    @ObservationIgnored private let link: PeerLink
    /// Sends one message to one HomePad, the link by default. Tests put a HomePad
    /// in memory behind it.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    /// Commands waiting for their `CommandReply`, by command message ID.
    @ObservationIgnored private var pending: [UUID: PendingReply] = [:]

    private struct PendingReply {
        let peerID: String
        let continuation: CheckedContinuation<CommandReply, Error>
        let timeout: Task<Void, Never>
    }

    init(link: PeerLink) {
        self.link = link
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
    }

    func start() {
        link.on(.status) { [weak self] message, peer in
            guard let status = try? message.content(HomePadStatus.self) else { return }
            self?.statuses[peer.id] = status
        }
        link.on(.commandReply) { [weak self] message, peer in
            guard let reply = try? message.content(CommandReply.self) else { return }
            self?.finish(reply.commandID, from: peer.id, with: .success(reply))
        }
        link.onConnect { [weak self] peer in
            guard peer.kind == .homePad else { return }
            Task { await self?.refresh(peer.id) }
        }
    }

    public func status(of peerID: String) -> HomePadStatus? { statuses[peerID] }

    /// Every running or paused timer across HomePads, soonest first.
    public var timers: [(homePad: String, timer: HomeTimer)] {
        statuses.values
            .flatMap { status in status.timers.map { (status.name, $0) } }
            .sorted { $0.1.remaining() < $1.1.remaining() }
    }

    /// Scenes known to any HomePad, for companions without their own smart home setup.
    public var scenes: [HomeScene] {
        var seen = Set<String>()
        return statuses.values.flatMap(\.scenes).filter { seen.insert($0.id).inserted }
    }

    /// Asks one HomePad (or all) for fresh status.
    public func refresh(_ peerID: String? = nil) async {
        guard let message = try? link.message(.statusRequest, [String: String]()) else { return }
        _ = try? await link.send(message, toHomePad: peerID)
    }

    /// Sends a command to one HomePad, or to all when `peerID` is nil, without
    /// waiting for an answer. Any HomePad understands these, however old.
    public func send(_ command: RemoteCommand, to peerID: String? = nil) async throws {
        let message = try link.message(.command, command)
        if try await link.send(message, toHomePad: peerID).isEmpty {
            throw PeerLinkError.peerUnavailable("No HomePad")
        }
    }

    /// Sends a command to one HomePad and waits for its answer. Returns the
    /// HomePad's sentence about it, if any.
    ///
    /// Throws `RemoteError.updateRequired` without sending anything when the
    /// HomePad's status says it is too old for the command, and also when the
    /// HomePad answers that it cannot read it.
    @discardableResult
    public func perform(_ command: RemoteCommand, on peerID: String, timeout: Duration = .seconds(10)) async throws -> String? {
        guard let status = statuses[peerID] else {
            throw PeerLinkError.peerUnavailable(link.peer(peerID)?.name ?? "That HomePad")
        }
        guard status.understands(command) else { throw RemoteError.updateRequired(homePad: status.name) }
        let reply = try await request(command, on: peerID, timeout: timeout)
        switch reply.outcome {
        case .done: return reply.message
        case .failed: throw RemoteError.failed(reply.message ?? "That did not work on \(status.name).")
        case .unsupported: throw RemoteError.updateRequired(homePad: status.name)
        }
    }

    private func request(_ command: RemoteCommand, on peerID: String, timeout: Duration) async throws -> CommandReply {
        let message = try link.message(.command, command)
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(message.id, from: peerID, with: .failure(PeerLinkError.timedOut))
            }
            pending[message.id] = PendingReply(peerID: peerID, continuation: continuation, timeout: timer)
            Task { [weak self] in
                do {
                    try await self?.transmit(message, peerID)
                } catch {
                    self?.finish(message.id, from: peerID, with: .failure(error))
                }
            }
        }
    }

    /// Resumes the command waiting for this reply. A reply from any other
    /// device than the one asked is ignored.
    func finish(_ commandID: UUID, from peerID: String, with result: Result<CommandReply, Error>) {
        guard let entry = pending[commandID], entry.peerID == peerID else { return }
        pending[commandID] = nil
        entry.timeout.cancel()
        entry.continuation.resume(with: result)
    }
}

/// Why a remote command did not run, in words for the person.
public enum RemoteError: LocalizedError, Equatable {
    /// The HomePad runs a HomePad too old for the command.
    case updateRequired(homePad: String)
    /// The HomePad tried and said why it could not.
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .updateRequired(let homePad): RemoteControlServer.updateMessage(for: homePad)
        case .failed(let message): message
        }
    }
}
