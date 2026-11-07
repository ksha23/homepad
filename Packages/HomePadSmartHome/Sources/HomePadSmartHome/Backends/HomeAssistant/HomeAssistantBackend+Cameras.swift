import Foundation
import HAKit
import HomePadCore

extension HomeAssistantBackend {
    /// How often a still refreshes where video is not worth it.
    static let stillInterval: Duration = .seconds(10)

    /// `GET /api/camera_proxy/<entity>` returns the latest JPEG.
    func snapshot(of camera: HomeCamera) async throws -> Data? {
        guard let configuration else { throw SmartHomeError.notConnected(.homeAssistant) }
        let request = configuration.request(path: "api/camera_proxy/\(BackendID.localID(of: camera.id))")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SmartHomeError.backend("Home Assistant could not take a snapshot of \(camera.name).")
        }
        return data
    }

    /// The best feed that has not failed yet, in `HACameraFeedPlan`'s order. Asks
    /// for the camera's capabilities each time, since a WebRTC provider can register
    /// after the camera does without its state changing.
    func feed(for camera: HomeCamera, purpose: CameraFeedPurpose, excluding failed: Set<CameraFeedKind>) async -> CameraFeed {
        guard let configuration else { return .unavailable("Home Assistant is not connected.") }
        let entityID = BackendID.localID(of: camera.id)
        let capabilities = purpose == .still ? nil : await capabilities(of: entityID)
        let supportsStream = states[entityID]?.supports(HAFeature.cameraStream) == true
        var failed = failed
        while true {
            let kind = HACameraFeedPlan.next(for: purpose, capabilities: capabilities,
                                             supportsStream: supportsStream, excluding: failed)
            switch kind {
            case .webRTC:
                guard let connection else {
                    failed.insert(.webRTC)
                    continue
                }
                return .webRTC(HAWebRTCSource(
                    entityID: entityID,
                    receivesAudio: purpose == .fullScreen,
                    offersTalk: purpose == .fullScreen && capabilities?.twoWayAudio == true,
                    transport: HAKitWebRTCTransport(connection: connection)
                ))
            case .hls:
                if let url = await hlsURL(of: entityID, baseURL: configuration.baseURL) { return .hls(url) }
                failed.insert(.hls)
            case .mjpeg:
                return .mjpeg(configuration.request(path: "api/camera_proxy_stream/\(entityID)"))
            case .stills:
                return .stills(every: Self.stillInterval)
            }
        }
    }

    /// Nil when Home Assistant does not answer, as before 2024.11.
    private func capabilities(of entityID: String) async -> HACameraCapabilities? {
        // A request waits for a connection that is down, which would hold the feed back.
        guard status.isConnected, let connection, let result = try? await connection.send(HARequests.cameraCapabilities(entityID)) else { return nil }
        return HACameraCapabilities(json: JSONValue(haData: result))
    }

    /// Asking starts Home Assistant's stream worker, so it happens only once HLS is next.
    private func hlsURL(of entityID: String, baseURL: URL) async -> URL? {
        guard status.isConnected, let connection, let result = try? await connection.send(HARequests.cameraStream(entityID)) else { return nil }
        return HAResponses.streamURL(JSONValue(haData: result), baseURL: baseURL)
    }

    func history(for accessory: HomeAccessory, hours: Double) async -> [SensorSample] {
        guard let connection else { return [] }
        let request = HARequests.history(BackendID.localID(of: accessory.id), since: Date().addingTimeInterval(-hours * 3600))
        guard let data = try? await connection.send(request) else { return [] }
        return HAResponses.history(JSONValue(haData: data))
    }
}
