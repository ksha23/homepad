import Foundation
import HAKit
import HomePadCore

extension HomeAssistantBackend {
    /// Forwards HAKit connection state changes (delivered on the main queue).
    final class ConnectionObserver: HAConnectionDelegate {
        let handler: (HAConnectionState) -> Void

        init(handler: @escaping (HAConnectionState) -> Void) {
            self.handler = handler
        }

        func connection(_ connection: HAConnection, didTransitionTo state: HAConnectionState) {
            handler(state)
        }
    }

    /// Connects when a configuration exists. HAKit reconnects on its own after drops.
    func start() {
        disconnect()
        guard let configuration else {
            status = .notConfigured
            onChange?()
            return
        }
        let connection = makeConnection(HAConnectionConfiguration(
            connectionInfo: { try? HAConnectionInfo(url: configuration.baseURL, userAgent: "HomePad") },
            fetchAuthToken: { completion in completion(.success(configuration.token)) }
        ))
        let observer = ConnectionObserver { [weak self] state in
            MainActor.assumeIsolated { self?.connectionDidTransition(to: state) }
        }
        connection.delegate = observer
        connectionObserver = observer
        self.connection = connection
        subscribe(on: connection)
        openPushChannel(on: connection)
        status = .connecting
        onChange?()
        connection.connect()
    }

    func disconnect() {
        registryReloadTask?.cancel()
        registryReloadTask = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        pushChannel?.cancel()
        pushChannel = nil
        connection?.disconnect()
        connection?.delegate = nil
        connection = nil
        connectionObserver = nil
    }

    /// HAKit keeps these subscriptions alive across reconnects, so they are made
    /// once per connection and cancelled in `disconnect`.
    private func subscribe(on connection: HAConnection) {
        subscriptions.append(connection.subscribe(to: .stateChanged()) { [weak self] _, event in
            MainActor.assumeIsolated { self?.apply(HAStateChange(event: event)) }
        })
        for type in HARegistry.updateEventTypes {
            subscriptions.append(connection.subscribe(to: .events(HAEventType(rawValue: type))) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRegistryReload() }
            })
        }
    }

    /// Loads the registries again once a burst of registry events has passed.
    /// Each event used to start its own reload of all three registries.
    func scheduleRegistryReload() {
        registryReloadTask?.cancel()
        registryReloadTask = Task { [weak self, registryReloadDelay] in
            try? await Task.sleep(for: registryReloadDelay)
            guard !Task.isCancelled, let self else { return }
            self.registryReloadTask = nil
            await self.loadRegistries()
        }
    }

    private func connectionDidTransition(to state: HAConnectionState) {
        switch state {
        case .connecting, .authenticating:
            status = .connecting
        case .ready(let version):
            status = .connected(detail: "version \(version)")
            // Home Assistant ends every WebRTC session with the WebSocket, so live views start again.
            connectionEpoch += 1
            Task { await loadInitialData() }
        case .disconnected(.rejected):
            status = .failed("Home Assistant rejected the access token.")
        case .disconnected(.waitingToReconnect(_, let date, _)):
            status = .reconnecting(retryAt: date)
        case .disconnected(.disconnected):
            status = configuration == nil ? .notConfigured : .reconnecting(retryAt: nil)
        }
        log.info("Connection is now \(self.status.summary, privacy: .public)")
        onChange?()
    }

    /// Runs after every (re)connect: server config, registries for room names, then all states.
    func loadInitialData() async {
        guard let connection else { return }
        if let data = try? await connection.send(HARequests.config), connection === self.connection {
            serverConfig = HAServerConfig(json: JSONValue(haData: data))
        }
        await loadRegistries()
        await refresh()
    }

    func loadRegistries() async {
        guard let connection else { return }
        do {
            async let areas = connection.send(HARequests.areaRegistry)
            async let devices = connection.send(HARequests.deviceRegistry)
            async let entities = connection.send(HARequests.entityRegistry)
            let loaded = try await HARegistry(
                areas: JSONValue(haData: areas),
                devices: JSONValue(haData: devices),
                entities: JSONValue(haData: entities)
            )
            // A new address or token replaced the connection while this was loading.
            guard connection === self.connection else { return }
            registry = loaded
            scheduleRebuild()
        } catch {
            log.error("Loading registries failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
