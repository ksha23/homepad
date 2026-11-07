import Foundation
import HomePadCore

/// A notification from Home Assistant shown as a banner.
struct HomeAssistantNotification: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var message: String?
}

/// Running what Home Assistant sends, through the same events and services a
/// tap would use. Screens open through the shell, so a personal app still waits
/// behind the recognition gate.
extension HomeAssistantDevice {
    /// One event from the push channel.
    func receive(_ event: JSONValue) {
        guard isReporting else { return }
        perform(MobileAppCommand.parse(event))
    }

    func perform(_ command: MobileAppCommand) {
        let events = services.events
        switch command {
        case .sleep:
            events.post(.sleepDisplay)
        case .wake:
            events.post(.wake)
        case .showCamera(let entityID):
            let id = BackendID.make(.homeAssistant, entityID)
            guard smartHome.camera(id) != nil else {
                return log.info("kiosk_show_camera: \(entityID, privacy: .public) is not a camera HomePad shows")
            }
            smartHome.showCamera(id)
        case .hideCamera:
            smartHome.cameraRequest = .close
        case .setBrightness(let level):
            events.post(.setBrightness(level))
        case .setVolume(let level):
            Task { await services.media.setVolume(level) }
        case .reload:
            // What a reconnect loads: the server config, the registries, then every state.
            Task { await backend.loadInitialData() }
        case .showDefaultFace:
            events.post(.showDefaultFace)
        case .showFace(let face):
            guard let face else { return events.post(.showDefaultFace) }
            guard let id = faceID(matching: face) else {
                return log.info("homepad_show_face: no face \(face, privacy: .public)")
            }
            events.post(.showFace(id: id))
        case .goHome:
            // The shell's own link, which also wakes the screen.
            events.post(.custom(name: ConnectEventName.openURL, payload: "homepad://home"))
        case .openApp(let app):
            guard let id = appID(matching: app) else {
                return log.info("homepad_open_app: no app \(app, privacy: .public)")
            }
            events.post(.openApp(id: id))
        case .speak(let text, let title):
            show(HomeAssistantNotification(title: title ?? "Home Assistant", message: text))
            // Quiet Hours keep it to the banner, as they do chimes and intercom.
            if !services.settings[CoreSettings.quietHoursEnabled] { events.post(.speak(text)) }
        case .banner(let title, let message):
            show(title.map { HomeAssistantNotification(title: $0, message: message) }
                 ?? HomeAssistantNotification(title: message, message: nil))
        case .ignored(let reason):
            log.info("Home Assistant notification ignored: \(reason, privacy: .public)")
        }
    }

    /// Shows a banner for a while and wakes the screen so it can be read.
    func show(_ notification: HomeAssistantNotification) {
        self.notification = notification
        services.events.post(.wake)
        notificationTask?.cancel()
        notificationTask = Task { [weak self, notificationDuration] in
            try? await Task.sleep(for: notificationDuration)
            guard !Task.isCancelled, let self, self.notification?.id == notification.id else { return }
            self.notification = nil
        }
    }

    func dismissNotification() {
        notificationTask?.cancel()
        notification = nil
    }

    /// A face by ID, or by its name as the Faces app shows it.
    func faceID(matching text: String) -> String? {
        guard let faces = registry?.faces else { return nil }
        if faces.contains(where: { $0.id == text }) { return text }
        return faces.first { $0.title.caseInsensitiveCompare(text) == .orderedSame }?.id
    }

    /// An app by ID (redirects such as `cameras` too), or by its name on the Home Screen.
    func appID(matching text: String) -> String? {
        guard let registry else { return nil }
        if registry.app(text) != nil || registry.redirect(text) != nil { return text }
        return registry.apps.first { $0.title.caseInsensitiveCompare(text) == .orderedSame }?.id
    }

    // MARK: Removing

    /// Deletes this HomePad's device from Home Assistant, when the token is an
    /// administrator's, and forgets the registration. The device ID stays, so
    /// adding the HomePad again replaces anything Home Assistant kept.
    func removeFromHomeAssistant() async {
        let name = registration?.deviceName ?? deviceName
        let configuration = backend.configuration
        isRemoving = true
        isEnabled = false
        stopReporting()
        status = .off
        var message: String
        do {
            guard let configuration, backend.status.isConnected else { throw SmartHomeError.notConnected(.homeAssistant) }
            let devices = try await backend.sendCommand("config/device_registry/list", data: [:])
            if let entryID = MobileAppRegistration.configEntryID(deviceID: store.deviceID(), deviceRegistry: devices) {
                try await transport.deleteConfigEntry(entryID, on: configuration)
                message = "Removed \(name) from Home Assistant."
            } else {
                message = "Home Assistant has no device for this HomePad."
            }
        } catch {
            message = "\(error.localizedDescription) Delete \(name) in Home Assistant under Settings, Devices & services, Mobile App."
        }
        save(nil)
        throttle.reset()
        removalMessage = message
        isRemoving = false
    }
}
