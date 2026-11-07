import Foundation
import HAKit
import HomePadCore

/// One `state_changed` event.
struct HAStateChange: Sendable {
    var entityID: String
    var oldState: HAState?
    var newState: HAState?

    init(entityID: String, oldState: HAState?, newState: HAState?) {
        self.entityID = entityID
        self.oldState = oldState
        self.newState = newState
    }

    init(event: HAResponseEventStateChanged) {
        self.init(
            entityID: event.entityId,
            oldState: event.oldState.map(HAState.init(entity:)),
            newState: event.newState.map(HAState.init(entity:))
        )
    }
}
