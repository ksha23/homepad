import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// The action each kind of tracker gets for Play Sound.
@Suite struct HAPlaySoundCallTests {
    let registry = Fixtures.trackerRegistry()
    let states: [String: HAState]
    let accounts: [SmartHomeIntegrationEntry]

    init() throws {
        states = Dictionary(uniqueKeysWithValues: try Fixtures.states("rest_states_trackers").map { ($0.entityID, $0) })
        let entries = JSONValue(haData: Fixtures.resultData("ws_result_config_entries_icloud"))
        accounts = (entries.arrayValue ?? []).compactMap(SmartHomeIntegrationEntry.init(json:))
    }

    func call(_ entityID: String, accounts: [SmartHomeIntegrationEntry]? = nil, registry: HARegistry? = nil) throws -> HAServiceCall {
        try HAPlaySoundCall.call(entityID: entityID, state: states[entityID], registry: registry ?? self.registry,
                                 iCloudAccounts: accounts ?? self.accounts)
    }

    @Test func iCloudUsesTheTrackersOwnAccountAndFindMyName() throws {
        let kyle = try call("device_tracker.kyles_iphone")
        #expect(kyle.domain == "icloud")
        #expect(kyle.service == "play_sound")
        #expect(kyle.data == ["account": "kyle@example.com", "device_name": "Kyle\u{2019}s iPhone"])
        #expect(kyle.entityID == nil)
        let sam = try call("device_tracker.sams_iphone")
        #expect(sam.data["account"] == "sam@example.com")
    }

    @Test func aRenameInHomeAssistantKeepsTheFindMyName() throws {
        var registry = registry
        registry.entities["device_tracker.kyles_iphone"]?.name = "Kyle Phone"
        registry.devices["dev_kyles_iphone"]?.name = "Kyle Phone"
        #expect(try call("device_tracker.kyles_iphone", registry: registry).data["device_name"] == "Kyle\u{2019}s iPhone")
        // Without a device the tracker's friendly name is the next best guess, never its model.
        registry.entities["device_tracker.kyles_iphone"]?.deviceID = nil
        #expect(try call("device_tracker.kyles_iphone", registry: registry).data["device_name"] == "Kyle\u{2019}s iPhone")
    }

    @Test func theOnlyICloudAccountIsUsedWhenTheEntryIsUnknown() throws {
        var registry = registry
        registry.entities["device_tracker.kyles_iphone"]?.configEntryID = nil
        let only = Array(accounts.prefix(1))
        #expect(try call("device_tracker.kyles_iphone", accounts: only, registry: registry).data["account"] == "kyle@example.com")
        #expect(throws: SmartHomeError.self) { try call("device_tracker.kyles_iphone", registry: registry) }
        #expect(throws: SmartHomeError.self) { try call("device_tracker.kyles_iphone", accounts: []) }
    }

    @Test func companionAppRingsWithACriticalNotification() throws {
        let iPad = try call("device_tracker.kyles_ipad")
        #expect(iPad.domain == "notify")
        // Named after the registered name, not the "Kitchen iPad" rename.
        #expect(iPad.service == "mobile_app_kyle_s_ipad")
        #expect(iPad.data["message"]?.stringValue == HAPlaySoundCall.message)
        let sound = iPad.data["data"]?["push"]?["sound"]
        #expect(sound?["name"] == "default")
        #expect(sound?["critical"]?.intValue == 1)
        #expect(sound?["volume"]?.doubleValue == 1)
        #expect(iPad.data["data"]?["channel"] == "alarm_stream")
    }

    @Test func otherIntegrationsCannotRing() {
        #expect(throws: SmartHomeError.self) { try call("device_tracker.jordans_phone") }
    }

    @Test func slugMatchesHomeAssistant() {
        #expect(HAPlaySoundCall.slug("Kyle\u{2019}s iPhone") == "kyle_s_iphone")
        #expect(HAPlaySoundCall.slug("Kyle's iPad Pro (M5)") == "kyle_s_ipad_pro_m5")
        #expect(HAPlaySoundCall.slug("Zoë’s  iPad") == "zoe_s_ipad")
        #expect(HAPlaySoundCall.slug("  ") == "unknown")
        #expect(HAPlaySoundCall.notifyService(forDeviceNamed: "Sam's iPhone") == "mobile_app_sam_s_iphone")
    }
}
