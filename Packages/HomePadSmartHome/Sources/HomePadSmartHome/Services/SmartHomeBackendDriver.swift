import Foundation
import HomePadCore

/// One smart home system behind the unified service. Every ID a driver produces
/// already carries its backend prefix (see `BackendID`).
@MainActor
protocol SmartHomeBackendDriver: AnyObject {
    var backend: SmartHomeBackend { get }
    var accessories: [HomeAccessory] { get }
    var scenes: [HomeScene] { get }
    var cameras: [HomeCamera] { get }
    var status: BackendStatus { get }
    /// Set up by the person. While any real backend is configured the demo steps aside.
    var isConfigured: Bool { get }

    /// Called by the driver whenever its accessories, scenes, cameras or status change.
    var onChange: (() -> Void)? { get set }
    /// Called when a doorbell rings, with the unified camera ID when the driver knows it.
    var onDoorbell: ((HomeCamera.ID?) -> Void)? { get set }

    func start()
    func refresh() async
    func perform(_ command: AccessoryCommand, on accessory: HomeAccessory) async throws
    func activateScene(_ scene: HomeScene) async throws
    func snapshot(of camera: HomeCamera) async throws -> Data?
    /// The best feed for the purpose, leaving out kinds the view could not play.
    func feed(for camera: HomeCamera, purpose: CameraFeedPurpose, excluding failed: Set<CameraFeedKind>) async -> CameraFeed
    func callService(domain: String, service: String, data: JSONValue) async throws
    /// A raw command answered with data. Only Home Assistant supports it.
    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue
    func history(for accessory: HomeAccessory, hours: Double) async -> [SensorSample]
    func supportsTalk(_ camera: HomeCamera) -> Bool
    func setTalking(_ talking: Bool, camera: HomeCamera) async throws
}

extension SmartHomeBackendDriver {
    func callService(domain: String, service: String, data: JSONValue) async throws {
        throw SmartHomeError.unsupported("\(domain).\(service) on \(backend.displayName)")
    }

    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        throw SmartHomeError.unsupported("\(type) on \(backend.displayName)")
    }

    func history(for accessory: HomeAccessory, hours: Double) async -> [SensorSample] { [] }

    func supportsTalk(_ camera: HomeCamera) -> Bool { false }

    func setTalking(_ talking: Bool, camera: HomeCamera) async throws {
        throw SmartHomeError.unsupported("Talk")
    }
}
