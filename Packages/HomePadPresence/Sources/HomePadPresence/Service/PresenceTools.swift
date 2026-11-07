import Foundation
import HomePadCore

/// Assistant tools backed by presence sensing.
enum PresenceTools {
    /// "Is anyone in the kitchen?" style questions about this room.
    @MainActor
    static func status(presence: LivePresenceService, household: Household) -> AssistantTool {
        AssistantTool(
            name: "presence_status",
            description: "Reports whether anyone is near this HomePad, how many people, roughly how far away, whether they are looking at the screen, who was recognized, and the room's light level."
        ) { [weak presence, weak household] _ in
            guard let presence else { return "Presence sensing is not available." }
            let snapshot = presence.snapshot
            guard snapshot.isSomeonePresent else {
                return "Nobody is near the HomePad right now. Sensing mode: \(presence.mode.title)."
            }
            var parts = ["\(snapshot.peopleCount) \(snapshot.peopleCount == 1 ? "person" : "people") nearby"]
            parts.append("proximity \(snapshot.proximity.title.lowercased())")
            if let meters = snapshot.nearestDistanceMeters { parts.append(String(format: "about %.1f meters away", meters)) }
            if snapshot.isLookingAtScreen { parts.append("looking at the screen") }
            if let id = snapshot.recognizedMemberID, let name = household?.members.first(where: { $0.id == id })?.name {
                parts.append("recognized \(name)")
            }
            if let light = snapshot.ambientLight { parts.append("room light \(light.rawValue)") }
            return parts.joined(separator: ", ") + "."
        }
    }
}
