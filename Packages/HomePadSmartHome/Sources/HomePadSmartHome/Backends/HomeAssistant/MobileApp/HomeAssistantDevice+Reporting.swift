import Foundation
import HomePadCore

/// Sending sensor changes: whatever Home Assistant has not heard, through
/// `MobileAppReportThrottle`, one `update_sensor_states` request at a time.
extension HomeAssistantDevice {
    /// Something the sensors read changed. Sends now, or once the throttle and
    /// any backoff allow, with the values as they are by then.
    func inputsChanged() {
        guard isReporting, backend.status.isConnected, sendTask == nil, scheduledSend == nil else { return }
        guard !throttle.changes(in: readInputs().states).isEmpty else { return }
        let now = clock()
        let at = max(throttle.earliestSend(now: now), backoffUntil ?? now)
        let wait = at.timeIntervalSince(now)
        guard wait > 0 else { return sendChanges() }
        let generation = self.generation
        scheduledSend = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            self.scheduledSend = nil
            self.sendChanges()
        }
    }

    /// Sends what changed in one request, then looks again for what changed meanwhile.
    func sendChanges() {
        guard isReporting, let registration, let configuration = reportingConfiguration else { return }
        let changes = throttle.changes(in: readInputs().states)
        guard !changes.isEmpty else { return }
        throttle.noteSending(at: clock())
        let generation = self.generation
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.transport.send(MobileAppSensorState.updateMessage(changes),
                                                          webhookID: registration.webhookID, on: configuration)
                guard generation == self.generation else { return }
                try await self.handle(reply, sent: changes, registration: registration, configuration: configuration)
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                self.backOff(after: error)
            }
            guard generation == self.generation else { return }
            self.sendTask = nil
            self.inputsChanged()
        }
    }

    /// Notes what Home Assistant took, registers what it does not know, and
    /// registers the device again when the webhook is gone.
    private func handle(_ reply: MobileAppWebhookReply, sent: [MobileAppSensorState],
                        registration: MobileAppRegistration.Stored, configuration: HomeAssistantConfiguration) async throws {
        switch reply {
        case .gone, .unknownWebhook:
            registrationLost()
        case .handled(let result):
            let accepted = MobileAppSensorState.accepted(in: result)
            throttle.noteReported(sent.filter { accepted.contains($0.sensor) })
            // A sensor deleted in Home Assistant is registered again, with its value.
            for sensor in MobileAppSensorState.unregistered(in: result) {
                let state = readInputs().state(of: sensor)
                if case .handled(let answer) = try await transport.send(state.registerMessage,
                                                                         webhookID: registration.webhookID, on: configuration),
                   answer["success"]?.boolValue == true {
                    throttle.noteReported([state])
                }
            }
            if accepted.isEmpty, MobileAppSensorState.unregistered(in: result).isEmpty {
                throw SmartHomeError.backend("Home Assistant did not take the sensor update.")
            }
            backoff = 30
            backoffUntil = nil
        }
    }

    /// Waits before the next update, longer after each failure, so a Home
    /// Assistant that is down or refusing is not asked every five seconds.
    private func backOff(after error: Error) {
        log.error("Sending sensor changes failed: \(error.localizedDescription, privacy: .public)")
        backoffUntil = clock().addingTimeInterval(backoff)
        backoff = min(backoff * 2, 600)
    }
}
