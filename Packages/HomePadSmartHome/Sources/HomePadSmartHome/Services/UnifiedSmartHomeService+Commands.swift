import Foundation
import HomePadCore

extension UnifiedSmartHomeService {
    func refresh() async {
        for driver in activeDrivers {
            await driver.refresh()
        }
    }

    /// From other modules and the assistant. Unlocking or opening needs a recognized member.
    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws {
        try await perform(command, on: accessoryID, confirmed: false)
    }

    /// - Parameter confirmed: True when the person confirmed on screen, which lets a
    ///   guest unlock or open. Only HomePad's own controls pass true.
    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID, confirmed: Bool) async throws {
        let accessoryID = localID(for: accessoryID)
        guard let accessory = allAccessories.first(where: { $0.id == accessoryID }) else {
            throw SmartHomeError.accessoryNotFound(accessoryID)
        }
        if SecurityPolicy.isSensitive(command, on: accessory), !confirmed, !household.isPersonalContentUnlocked {
            throw SmartHomeError.requiresRecognizedMember
        }
        try await driver(for: accessory.backend).perform(command, on: accessory)
    }

    func activateScene(_ sceneID: HomeScene.ID) async throws {
        let sceneID = localID(for: sceneID)
        guard let scene = scenes.first(where: { $0.id == sceneID }) else { throw SmartHomeError.accessoryNotFound(sceneID) }
        try await driver(for: scene.backend).activateScene(scene)
    }

    /// Raw Home Assistant service call. Calls that unlock, open a door or disarm need
    /// a recognized member, because there is no on-screen confirmation here.
    func callService(domain: String, service: String, data: JSONValue) async throws {
        guard homeAssistant.isConfigured else { throw SmartHomeError.notConnected(.homeAssistant) }
        let call = HAServiceCall(domain: domain, service: service, data: data.objectValue ?? [:])
        try requireAllowed(domain: domain, service: service, entityIDs: call.targetEntityIDs)
        try await homeAssistant.execute(call)
    }

    /// Raw Home Assistant command with a result, such as `config_entries/get` or an action
    /// call with `return_response`. Only `SecurityPolicy.allowedRawCommands` pass, and
    /// action calls follow the same rules as `callService`.
    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        guard homeAssistant.isConfigured else { throw SmartHomeError.notConnected(.homeAssistant) }
        guard SecurityPolicy.allowedRawCommands.contains(type) else { throw SmartHomeError.unsupported(type) }
        if type == SmartHomeCommandType.callService {
            try requireAllowed(
                domain: data["domain"]?.stringValue ?? "", service: data["service"]?.stringValue ?? "",
                entityIDs: SecurityPolicy.targetEntityIDs(serviceData: data["service_data"], target: data["target"])
            )
        }
        return try await homeAssistant.sendCommand(type, data: data)
    }

    /// Calls that unlock, open a door or disarm need a recognized member.
    private func requireAllowed(domain: String, service: String, entityIDs: [String]) throws {
        let sensitive = SecurityPolicy.isSensitiveServiceCall(
            domain: domain, service: service, entityIDs: entityIDs, kindOf: homeAssistant.kind(ofEntity:)
        )
        if sensitive, !household.isPersonalContentUnlocked {
            throw SmartHomeError.requiresRecognizedMember
        }
    }

    // MARK: Find My

    /// Plays a sound on a tracked device. Locations and devices are personal, so
    /// it needs a recognized member, like the Find My app and the assistant's tools.
    func playSound(onTrackedDevice id: TrackedDevice.ID) async throws {
        guard household.isPersonalContentUnlocked else { throw SmartHomeError.requiresRecognizedMember }
        guard let device = trackedDevices.first(where: { $0.id == id }) else { throw SmartHomeError.accessoryNotFound(id) }
        guard device.canPlaySound else { throw HAPlaySoundCall.cannotRing(device.name) }
        try await homeAssistant.playSound(on: device)
    }

    // MARK: Cameras

    func snapshot(cameraID: HomeCamera.ID) async throws -> Data? {
        guard let camera = camera(cameraID) else { throw SmartHomeError.accessoryNotFound(cameraID) }
        return try await driver(for: camera.backend).snapshot(of: camera)
    }

    func feed(for cameraID: HomeCamera.ID, purpose: CameraFeedPurpose, excluding failed: Set<CameraFeedKind> = []) async -> CameraFeed {
        guard let camera = camera(cameraID) else { return .unavailable("This camera is no longer available.") }
        return await driver(for: camera.backend).feed(for: camera, purpose: purpose, excluding: failed)
    }

    func supportsTalk(cameraID: HomeCamera.ID) -> Bool {
        guard let camera = camera(cameraID) else { return false }
        return driver(for: camera.backend).supportsTalk(camera)
    }

    func setTalking(_ talking: Bool, cameraID: HomeCamera.ID) async throws {
        guard let camera = camera(cameraID) else { throw SmartHomeError.accessoryNotFound(cameraID) }
        try await driver(for: camera.backend).setTalking(talking, camera: camera)
    }

    func history(for accessoryID: HomeAccessory.ID, hours: Double = 24) async -> [SensorSample] {
        let accessoryID = localID(for: accessoryID)
        guard let accessory = allAccessories.first(where: { $0.id == accessoryID }) else { return [] }
        return await driver(for: accessory.backend).history(for: accessory, hours: hours)
    }

    // MARK: Doorbell

    /// The camera to show when the doorbell rings: the person's pick, then a doorbell camera, then any camera.
    var doorbellCameraID: HomeCamera.ID? {
        doorbell.cameraID
            ?? allCameras.first(where: \.isDoorbell)?.id
            ?? allCameras.first?.id
    }

    /// The lock the doorbell overlay offers to unlock: the person's pick, then a lock in the
    /// doorbell camera's room, then one named like a front door, then the only lock.
    var doorbellLock: HomeAccessory? {
        let locks = allAccessories.filter { $0.kind == .lock }
        if let id = doorbell.lockID { return locks.first { $0.id == id } }
        let room = doorbellCameraID.flatMap(camera)?.room
        return locks.first { room != nil && $0.room == room }
            ?? locks.first { $0.name.localizedCaseInsensitiveContains("front") }
            ?? (locks.count == 1 ? locks.first : nil)
    }

    /// Posts `.doorbellRang` for the person's chosen camera, else the one the backend reported.
    func doorbellRang(cameraID: HomeCamera.ID?) {
        guard let resolved = doorbell.cameraID ?? cameraID ?? doorbellCameraID else {
            log.error("Doorbell rang but there is no camera to show")
            return
        }
        events.post(.doorbellRang(cameraID: resolved))
    }
}
