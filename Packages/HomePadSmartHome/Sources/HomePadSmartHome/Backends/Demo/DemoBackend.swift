import Foundation
import HomePadCore
import Observation
import SwiftUI

/// Demo data for the simulator and for first launch. Builds on Core's
/// `DemoSmartHomeService` (which owns the command handling) and adds more
/// accessories, cameras and scenes. Active whenever no real backend is set up.
@MainActor
@Observable
final class DemoBackend: SmartHomeBackendDriver {
    let backend = SmartHomeBackend.demo
    let status = BackendStatus.connected(detail: "demo data")
    let isConfigured = false

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onDoorbell: ((HomeCamera.ID?) -> Void)?

    private let store: DemoSmartHomeService

    init() {
        store = DemoSmartHomeService()
        store.accessories += DemoSeedData.accessories
        store.cameras += DemoSeedData.cameras
        store.scenes += DemoSeedData.scenes
    }

    var accessories: [HomeAccessory] {
        let base = store.accessories
        return base + DemoSeedData.groups.compactMap { group in
            AccessoryGroups.group(id: group.id, name: group.name, backend: .demo, members: base.filter { $0.groupID == group.id })
        }
    }
    var scenes: [HomeScene] { store.scenes }
    var cameras: [HomeCamera] { store.cameras }

    func start() {}

    func refresh() async {}

    func perform(_ command: AccessoryCommand, on accessory: HomeAccessory) async throws {
        if accessory.isGroup {
            let memberCommand = AccessoryGroups.memberCommand(command, group: accessory)
            for member in accessories where member.groupID == accessory.id {
                try await store.perform(memberCommand, on: member.id)
            }
            onChange?()
            return
        }
        try await store.perform(command, on: accessory.id)
        if accessory.kind == .garageDoor || accessory.kind == .cover, let index = store.accessories.firstIndex(where: { $0.id == accessory.id }) {
            let position = store.accessories[index].state.position ?? 0
            store.accessories[index].state.doorState = position > 0.01 ? .open : .closed
        }
        onChange?()
    }

    func activateScene(_ scene: HomeScene) async throws {
        for (accessoryID, command) in DemoSeedData.sceneActions[scene.id] ?? [] {
            try await store.perform(command, on: accessoryID)
        }
        onChange?()
    }

    /// Renders the animated demo scene to a JPEG, so other modules get a real image.
    func snapshot(of camera: HomeCamera) async throws -> Data? {
        let renderer = ImageRenderer(content: DemoCameraFeedView(camera: camera, date: Date()).frame(width: 640, height: 360))
        return renderer.uiImage?.jpegData(compressionQuality: 0.8)
    }

    func feed(for camera: HomeCamera, purpose: CameraFeedPurpose, excluding failed: Set<CameraFeedKind>) async -> CameraFeed {
        .demo(camera)
    }

    /// A smooth made-up day of readings around the current value.
    func history(for accessory: HomeAccessory, hours: Double) async -> [SensorSample] {
        guard let current = accessory.state.sensorValue ?? accessory.state.currentTemperature else { return [] }
        let now = Date()
        let count = 48
        return (0...count).map { step in
            let fraction = Double(step) / Double(count)
            let wave = sin(fraction * .pi * 2.2) * 1.6 + sin(fraction * .pi * 9) * 0.3
            return SensorSample(date: now.addingTimeInterval(-hours * 3600 * (1 - fraction)), value: current + wave * (1 - fraction))
        }
    }

    /// The demo doorbell pretends to support two-way audio so the talk button can be seen.
    func supportsTalk(_ camera: HomeCamera) -> Bool { camera.isDoorbell }

    func setTalking(_ talking: Bool, camera: HomeCamera) async throws {}
}
