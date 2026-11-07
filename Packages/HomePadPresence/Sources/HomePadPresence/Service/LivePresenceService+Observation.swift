import Foundation
import HomePadCore
import Observation

extension LivePresenceService {
    /// Everything outside Presence that changes what sensing should do.
    struct ObservedConditions: Equatable, Sendable {
        var settingsRevision: Int
        var sensingAllowed: Bool
        var claimOwner: String?
        var memberIDs: [UUID]
        var assistantPhase: AssistantPhase
    }

    /// Watches settings, camera claims, household members, the assistant and
    /// requests from other modules, and re-applies the duty cycle on change.
    func startObserving() {
        guard observationTasks.isEmpty else { return }
        conditions.onChange = { [weak self] in
            self?.refreshFeatures()
            self?.reevaluate()
        }
        conditions.onProtectedDataAvailable = { [weak self] in
            self?.recognition.load()
            self?.warmUpRecognition()
        }
        let services = self.services
        let changes = Observations { @MainActor in
            ObservedConditions(
                settingsRevision: services.settings.revision,
                sensingAllowed: services.capture.isPresenceSensingAllowed,
                claimOwner: services.capture.foregroundClaim?.owner,
                memberIDs: services.household.members.map(\.id),
                assistantPhase: services.assistant.phase
            )
        }
        observationTasks.append(Task { [weak self] in
            var previous: ObservedConditions?
            for await state in changes {
                self?.conditionsChanged(from: previous, to: state)
                previous = state
            }
        })
        let events = services.events.stream()
        observationTasks.append(Task { [weak self] in
            for await event in events {
                self?.handleRequest(event)
            }
        })
    }

    private func conditionsChanged(from old: ObservedConditions?, to new: ObservedConditions) {
        if old?.memberIDs != new.memberIDs {
            recognition.reconcile(with: services.household.members)
        }
        if old?.settingsRevision != new.settingsRevision {
            refreshFeatures()
        }
        // An answer being spoken is the moment a yes or no question is likely.
        if new.assistantPhase == .speaking, old?.assistantPhase != .speaking {
            headGestures.listen(for: 12)
        }
        reevaluate()
    }

    private func handleRequest(_ event: HomePadEvent) {
        guard case .custom(let name, let payload) = event else { return }
        switch name {
        case PresenceRequest.listenForHeadGestures:
            headGestures.listen(for: payload.doubleValue ?? 8)
        case SensingPermissionRequest.name:
            Task { await requestPermissions() }
        default:
            break
        }
    }
}
