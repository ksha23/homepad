import Foundation
import HomePadCore

/// Builds the accessory that stands for a group of accessories, the way Apple
/// Home shows one tile for a group: on when any member is on, reachable when
/// any member responds, and only the controls every member has.
enum AccessoryGroups {
    /// The group's accessory, or nil when it has no members.
    static func group(id: String, name: String, backend: SmartHomeBackend, members: [HomeAccessory]) -> HomeAccessory? {
        guard let first = members.first else { return nil }
        let rooms = Set(members.compactMap(\.room))
        return HomeAccessory(
            id: id, name: name,
            room: rooms.count == 1 ? rooms.first : first.room,
            kind: commonKind(members),
            backend: backend,
            capabilities: members.dropFirst().reduce(first.capabilities) { $0.intersection($1.capabilities) },
            state: state(of: members),
            memberIDs: members.map(\.id)
        )
    }

    /// The group's state, read from its members.
    static func state(of members: [HomeAccessory]) -> AccessoryState {
        let reachable = members.filter(\.state.isReachable)
        let on = reachable.filter { $0.state.isOn == true }
        var state = (on.first ?? reachable.first ?? members.first)?.state ?? AccessoryState()
        state.isReachable = !reachable.isEmpty
        if members.contains(where: { $0.state.isOn != nil }) { state.isOn = !on.isEmpty }
        if let brightness = average(on.compactMap(\.state.brightness)) { state.brightness = brightness }
        if let position = average(reachable.compactMap(\.state.position)) { state.position = position }
        // One unlocked door leaves the group unlocked.
        if reachable.contains(where: { $0.state.lockState == .unlocked }) { state.lockState = .unlocked }
        return state
    }

    /// The command each member gets. A toggle becomes an explicit on or off, so
    /// a group with some members on and some off ends up all one way.
    static func memberCommand(_ command: AccessoryCommand, group: HomeAccessory) -> AccessoryCommand {
        guard command == .toggle else { return command }
        return .setPower(group.state.isOn != true)
    }

    private static func commonKind(_ members: [HomeAccessory]) -> AccessoryKind {
        let counts = Dictionary(members.map { ($0.kind, 1) }, uniquingKeysWith: +)
        return members.map(\.kind).max { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? .other
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
