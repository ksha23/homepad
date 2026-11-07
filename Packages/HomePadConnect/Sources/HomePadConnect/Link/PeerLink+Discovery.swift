import Foundation
import HomePadCore
import Network

// Bonjour advertising, browsing and inbound connections.
extension PeerLink {
    /// Starts advertising and browsing. Safe to call more than once.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        problem = nil
        startListener()
        startBrowser()
    }

    public func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        dropAllSessions()
        peers = []
        endpoints = [:]
        isRunning = false
    }

    /// Starts again from nothing: new advertising, browsing and sessions.
    /// A companion woken in the background calls it, because iOS may have
    /// closed its sockets while it was suspended, and a session that looks
    /// open could be dead. Browsing finds the HomePads again and dials them.
    public func restart() {
        stop()
        start()
    }

    /// Re-reads the room name and re-advertises (after a settings change).
    public func refreshIdentity() {
        identity = LocalDevice.identity(settings: services.settings)
        readvertise()
    }

    /// Publishes the current name, household and pairing state.
    func readvertise() {
        guard let listener else { return }
        listener.service = service()
    }

    private func service() -> NWListener.Service {
        let advert = PeerAdvert(deviceID: identity.deviceID, name: identity.name, kind: identity.kind,
                                householdID: household?.id, acceptsPairing: pairingWindow?.isOpen() == true)
        return NWListener.Service(name: identity.name, type: PeerAdvert.serviceType, domain: nil,
                                  txtRecord: NWTXTRecord(advert.txt).data)
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = service()
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            problem = "Could not start the HomePad link: \(error.localizedDescription)"
            log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .failed(let error), .waiting(let error):
            problem = Self.describe(error)
        case .ready:
            problem = nil
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let code = pairingWindow.flatMap { $0.isOpen() ? $0.code : nil }
        let engine = HandshakeEngine(role: .responder, local: identity, intent: .session,
                                     credentials: household, pairingCode: code)
        let peer = PeerConnection(connection: connection, engine: engine)
        track(peer)
        peer.start()
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: PeerAdvert.serviceType, domain: nil), using: Self.parameters())
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed(let error) = state { self?.problem = Self.describe(error) }
                if case .waiting(let error) = state { self?.problem = Self.describe(error) }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.updatePeers(from: results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func updatePeers(from results: Set<NWBrowser.Result>) {
        var seen: [String: (PeerAdvert, NWEndpoint)] = [:]
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  let advert = PeerAdvert(txt: txt.dictionary),
                  advert.deviceID != identity.deviceID else { continue }
            seen[advert.deviceID] = (advert, result.endpoint)
        }
        endpoints = seen.mapValues(\.1)
        var updated: [PeerDevice] = []
        for (id, entry) in seen {
            var device = entry.0.device
            device.isConnected = sessions[id]?.isEstablished == true
            updated.append(device)
        }
        // Keep connected peers that do not advertise (for example a backgrounded iPhone).
        updated += peers.filter { $0.isConnected && seen[$0.id] == nil }
        peers = updated.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
        connectToNewMembers()
    }

    /// Companions keep a session open to each HomePad so HomePads can push
    /// alerts and status. HomePads connect to each other once (lower ID dials).
    private func connectToNewMembers() {
        for peer in members where sessions[peer.id] == nil && dialWaiters[peer.id] == nil {
            let shouldDial = identity.kind.isCompanion
                ? peer.kind == .homePad
                : (peer.kind == .homePad && identity.deviceID < peer.id)
            guard shouldDial else { continue }
            Task { _ = try? await session(with: peer.id) }
        }
    }

    private static func describe(_ error: NWError) -> String {
        if case .dns(let code) = error, code == -65570 {   // kDNSServiceErr_PolicyDenied
            return "Allow Local Network access for HomePad in Settings to find your other devices."
        }
        return "The HomePad link is waiting for the network (\(error.localizedDescription))."
    }
}
