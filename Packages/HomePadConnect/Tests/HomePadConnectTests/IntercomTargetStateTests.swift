import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Intercom reopens on the room it was set to while that HomePad is reachable.
@MainActor
@Suite struct IntercomTargetStateTests {
    @Test func aRoomOutOfReachFallsBackToEverywhere() {
        let kitchen = IntercomTarget.device(id: "kitchen")
        #expect(kitchen.reachable(among: ["kitchen", "bedroom"]) == kitchen)
        #expect(kitchen.reachable(among: ["bedroom"]) == .everyone)
        #expect(IntercomTarget.everyone.reachable(among: []) == .everyone)
    }

    @Test func theTargetIsSharedAndKeepsLoading() throws {
        #expect(ConnectAppState.intercomTarget.scope == .household)
        for target in [IntercomTarget.everyone, .device(id: "kitchen")] {
            let data = try JSONEncoder().encode(target)
            #expect(try JSONDecoder().decode(IntercomTarget.self, from: data) == target)
        }
    }
}
