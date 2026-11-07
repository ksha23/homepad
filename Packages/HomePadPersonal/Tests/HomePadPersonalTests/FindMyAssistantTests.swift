import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// What the assistant hears and says about devices.
@MainActor
@Suite struct FindMyAssistantTests {
    func tool(_ name: String, _ fixture: FindMyFixture) throws -> AssistantTool {
        try #require(FindMyTools.make(findMy: fixture.findMy).first { $0.name == name })
    }

    func match(_ device: String?, owner: String? = nil, _ fixture: FindMyFixture) -> [String] {
        FindMyDeviceMatcher.matches(device: device, owner: owner, in: fixture.findMy.visibleDevices,
                                    me: fixture.findMy.recognizedMember).map(\.title)
    }

    @Test func toolsNeedARecognizedMember() {
        let fixture = FindMyFixture()
        let tools = FindMyTools.make(findMy: fixture.findMy)
        #expect(tools.map(\.name) == ["find_device", "play_sound_on_device"])
        #expect(tools.allSatisfy { $0.requiresRecognizedMember })
    }

    @Test func matchesWhatPeopleSay() {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        #expect(match("Kyle's iPhone", fixture) == ["Kyle\u{2019}s iPhone"])
        #expect(match("my iPad", fixture) == ["Kyle\u{2019}s iPad"])
        #expect(match("iPad", owner: "me", fixture) == ["Kyle\u{2019}s iPad"])
        #expect(match("phone", owner: "Sam", fixture) == ["Sam's iPhone"])
        #expect(match("everyone's phone", fixture) == ["Kyle\u{2019}s iPhone", "Jordan's Phone", "Sam's iPhone"])
        #expect(match("living room tablet", fixture) == ["Living Room iPad"])
        #expect(match(nil, owner: "everyone", fixture).count == 5)
        #expect(match("car keys", fixture).isEmpty)
    }

    @Test func findDeviceAnswersLikeAPerson() async throws {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        let answer = try await tool("find_device", fixture).handler(["device": "Kyle's iPhone"])
        #expect(answer.hasPrefix("Kyle\u{2019}s iPhone is at home, last seen "))
        #expect(answer.hasSuffix("ago, with 82% battery."))
        let iPad = try await tool("find_device", fixture).handler(["device": "iPad", "owner": "me"])
        #expect(iPad.hasPrefix("Kyle\u{2019}s iPad is near 120 State St, Madison, last seen "))
        #expect(iPad.hasSuffix("with 62% and charging battery."))
        let sam = try await tool("find_device", fixture).handler(["device": "phone", "owner": "Sam"])
        #expect(sam.hasPrefix("Sam's iPhone is at Work, last seen "))
    }

    @Test func findDeviceOnlyTellsWhatThePersonMaySee() async throws {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.sam)
        let answer = try await tool("find_device", fixture).handler(["device": "phone", "owner": "everyone"])
        #expect(answer.contains("Sam's iPhone"))
        #expect(!answer.contains("Kyle"))
        let missing = try await tool("find_device", fixture).handler(["device": "Kyle's iPhone"])
        #expect(missing.hasPrefix("I couldn't find"))
        #expect(!missing.contains("Kyle\u{2019}s iPhone is"))
    }

    @Test func pingRingsOneDeviceOrAsksWhich() async throws {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        let ping = try tool("play_sound_on_device", fixture)
        #expect(try await ping.handler(["device": "my iPad"]) == "Sent a loud alert to Kyle\u{2019}s iPad. It rings even on silent.")
        #expect(try await ping.handler(["device": "iPhone", "owner": "Kyle"]) == "Playing a sound on Kyle\u{2019}s iPhone.")
        #expect(fixture.smartHome.rung == ["ha:device_tracker.kyles_ipad", "ha:device_tracker.kyles_iphone"])
        let which = try await ping.handler(["device": "iPad"])
        #expect(which == "Which one: Kyle\u{2019}s iPad or Living Room iPad?")
        let life360 = try await ping.handler(["device": "Jordan's phone"])
        #expect(life360.contains("cannot play a sound"))
        #expect(fixture.smartHome.rung.count == 2)
    }

    @Test func setupProblemsAreExplained() async throws {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        fixture.smartHome.trackedDevices = []
        let answer = try await tool("find_device", fixture).handler([:])
        #expect(answer.contains("iCloud integration"))
    }

    @Test func wording() {
        let now = FindMyFixture.now
        #expect(FindMyWording.lastSeen(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(FindMyWording.lastSeen(now.addingTimeInterval(-120), now: now) == "2 minutes ago")
        let watch = TrackedDevice(id: "ha:watch", name: "Watch", source: .iCloud, place: .unknown, lastUpdated: now.addingTimeInterval(-7200))
        #expect(FindMyWording.sentence(title: "Kyle's Watch", device: watch, address: nil, now: now)
            == "Kyle's Watch is not sharing a location right now. Home Assistant last heard from it 2 hours ago.")
        var away = watch
        away.place = .away
        #expect(FindMyWording.place(away, address: nil) == "away from home")
        #expect(FindMyWording.source(TrackedDevice(id: "x", name: "x", source: .other, integration: "life360", lastUpdated: now))
            == "Located by Life360")
    }
}
