import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

@Suite("Accessory groups")
struct AccessoryGroupsTests {
    private func lamp(_ id: String, on: Bool, brightness: Double, reachable: Bool = true, room: String = "Living Room",
                      capabilities: Set<AccessoryCapability> = [.power, .brightness]) -> HomeAccessory {
        var state = AccessoryState(isOn: on, brightness: brightness)
        state.isReachable = reachable
        return HomeAccessory(id: id, name: id, room: room, kind: .light, backend: .homeKit,
                             capabilities: capabilities, state: state, groupID: "hk:group")
    }

    @Test func groupIsOnWhenAnyMemberIsOn() throws {
        let members = [lamp("a", on: true, brightness: 0.8), lamp("b", on: false, brightness: 0.2), lamp("c", on: true, brightness: 0.4)]
        let group = try #require(AccessoryGroups.group(id: "hk:group", name: "Lamps", backend: .homeKit, members: members))
        #expect(group.isGroup)
        #expect(group.memberIDs == ["a", "b", "c"])
        #expect(group.kind == .light)
        #expect(group.room == "Living Room")
        #expect(group.state.isOn == true)
        // Brightness is the average of the members that are on.
        #expect(abs((group.state.brightness ?? 0) - 0.6) < 0.0001)
    }

    @Test func groupIsOffWhenEveryMemberIsOffOrUnreachable() throws {
        let members = [lamp("a", on: false, brightness: 0.5), lamp("b", on: true, brightness: 0.5, reachable: false)]
        let group = try #require(AccessoryGroups.group(id: "hk:group", name: "Lamps", backend: .homeKit, members: members))
        #expect(group.state.isOn == false)
        #expect(group.state.isReachable)
    }

    @Test func groupKeepsOnlySharedControls() throws {
        let members = [lamp("a", on: true, brightness: 1, capabilities: [.power, .brightness, .color]),
                       lamp("b", on: true, brightness: 1, capabilities: [.power, .brightness])]
        let group = try #require(AccessoryGroups.group(id: "hk:group", name: "Lamps", backend: .homeKit, members: members))
        #expect(group.capabilities == [.power, .brightness])
    }

    @Test func toggleBecomesOneDirectionForEveryMember() throws {
        let mixed = try #require(AccessoryGroups.group(id: "hk:group", name: "Lamps", backend: .homeKit,
                                                       members: [lamp("a", on: true, brightness: 1), lamp("b", on: false, brightness: 1)]))
        #expect(AccessoryGroups.memberCommand(.toggle, group: mixed) == .setPower(false))
        let off = try #require(AccessoryGroups.group(id: "hk:group", name: "Lamps", backend: .homeKit,
                                                     members: [lamp("a", on: false, brightness: 1)]))
        #expect(AccessoryGroups.memberCommand(.toggle, group: off) == .setPower(true))
        #expect(AccessoryGroups.memberCommand(.setBrightness(0.3), group: off) == .setBrightness(0.3))
    }

    @Test func listsShowTheGroupInPlaceOfItsMembers() throws {
        let members = [lamp("a", on: true, brightness: 1), lamp("b", on: false, brightness: 1)]
        let group = try #require(AccessoryGroups.group(id: "hk:group", name: "Lamps", backend: .homeKit, members: members))
        let all = members + [group]
        #expect(all.hidingGroupMembers.map(\.id) == ["hk:group"])
        #expect(all.withoutGroups.map(\.id) == ["a", "b"])
        #expect(FavoriteDefaults.accessoryIDs(from: all) == ["hk:group"])
    }
}
