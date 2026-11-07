import Foundation
import HomePadCore
import Network

// Household pairing with a 6-digit code.
//
// Host (a HomePad): `openPairingWindow()` shows a code for three minutes and
// advertises `pair=1`. Joiner (a new iPhone, Mac or HomePad): picks the host and
// calls `join(_:code:)`. Both derive a key from the code and an ephemeral X25519
// agreement, prove it with HMAC, and the host hands over the household key sealed
// with that key. Five wrong codes close the window.
extension PeerLink {
    /// Shows a fresh code, creating the household on first use.
    @discardableResult
    public func openPairingWindow() -> PairingWindow {
        openPairingWindow(PairingWindow())
    }

    /// Shows `window`'s code. Debug builds pass a fixed code to pair simulators.
    @discardableResult
    func openPairingWindow(_ window: PairingWindow) -> PairingWindow {
        if household == nil {
            let created = HouseholdCredentials(name: services.settings[CoreSettings.householdName])
            HouseholdCredentials.save(created, to: services.keychain)
            household = created
        }
        // Devices join the HomePad that shows the code, so its setup is the one they take.
        if let household { services.settings[ConnectSettings.hostedHousehold] = household.id }
        pairingWindow = window
        readvertise()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PairingCode.lifetime))
            if self?.pairingWindow == window { self?.closePairingWindow() }
        }
        return window
    }

    public func closePairingWindow() {
        pairingWindow = nil
        readvertise()
    }

    /// Joins the household of `hostID` with the code shown on its screen.
    public func join(_ hostID: String, code: String) async throws {
        guard let normalized = PairingCode.normalize(code) else {
            throw PeerLinkError.pairingFailed("Enter the 6-digit code shown on the HomePad.")
        }
        guard let endpoint = endpoints[hostID] else {
            throw PeerLinkError.peerUnavailable(peer(hostID)?.name ?? "That HomePad")
        }
        joinContinuation?.resume(throwing: CancellationError())
        let engine = HandshakeEngine(role: .initiator, local: identity, intent: .pair,
                                     credentials: household, pairingCode: normalized)
        let connection = PeerConnection(connection: NWConnection(to: endpoint, using: Self.parameters()), engine: engine)
        joinConnectionID = ObjectIdentifier(connection)
        track(connection)
        let credentials = try await withCheckedThrowingContinuation { continuation in
            joinContinuation = continuation
            connection.start()
        }
        log.info("Joined household \(credentials.name, privacy: .public)")
    }

    /// Leaves the household. Other devices will no longer accept this one.
    public func leaveHousehold() {
        HouseholdCredentials.save(nil, to: services.keychain)
        household = nil
        pairingWindow = nil
        dropAllSessions()
        readvertise()
    }

    // MARK: Called by PeerLink

    func completeJoin(_ credentials: HouseholdCredentials, host: HelloBody) {
        HouseholdCredentials.save(credentials, to: services.keychain)
        household = credentials
        services.settings[CoreSettings.householdName] = credentials.name
        dropAllSessions()
        readvertise()
        upsertPeer(from: HelloBody(protocolVersion: host.protocolVersion, deviceID: host.deviceID, name: host.name,
                                   kind: host.kind, nonce: host.nonce, ephemeralKey: host.ephemeralKey,
                                   householdID: credentials.id, intent: .session), connected: false)
        joinConnectionID = nil
        joinContinuation?.resume(returning: credentials)
        joinContinuation = nil
    }

    func admitted(_ hello: HelloBody) {
        log.info("Admitted \(hello.name, privacy: .public) to the household")
        closePairingWindow()
    }

    func connectionClosed(_ connection: PeerConnection, error: Error?) {
        if joinConnectionID == ObjectIdentifier(connection), let continuation = joinContinuation {
            joinConnectionID = nil
            joinContinuation = nil
            continuation.resume(throwing: Self.pairingError(error))
            return
        }
        if (error as? HandshakeError) == .wrongCode, var window = pairingWindow {
            window.failedAttempts += 1
            pairingWindow = window
            if !window.isOpen() { closePairingWindow() }
        }
    }

    private static func pairingError(_ error: Error?) -> PeerLinkError {
        switch error as? HandshakeError {
        case .rejected(.wrongCode): .pairingFailed("That code did not match. Check the HomePad and try again.")
        case .rejected(.pairingClosed), .rejected(.tooManyAttempts): .pairingFailed("That HomePad is not showing a code anymore. Open pairing on it again.")
        case .rejected(.unsupportedVersion), .unsupportedVersion: .pairingFailed("Update HomePad on both devices, then try again.")
        default: .pairingFailed("Pairing did not finish. Make sure both devices are on the same Wi-Fi.")
        }
    }
}
