import Foundation
import SwiftUI
import Testing
@testable import HomePadCore

/// Smart Rotate's rules: the most relevant widget wins, the stack returns to
/// the person's widget when that passes, and a flip by hand holds.
@Suite struct WidgetStackRotationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let ids = ["upnext", "weather", "music", "timers"]

    private func decide(_ relevance: [String: WidgetRelevance], chosen: String? = nil, chosenAt: Date? = nil,
                        smartRotate: Bool = true, at date: Date? = nil) -> WidgetStackRotation.Decision? {
        WidgetStackRotation.decide(memberIDs: ids, relevance: relevance, chosenID: chosen, chosenAt: chosenAt,
                                   smartRotate: smartRotate, now: date ?? now)
    }

    @Test func restsOnTheFirstWidgetWithNothingRelevant() {
        #expect(decide([:])?.memberID == "upnext")
        #expect(decide([:])?.nextCheck == nil)
        #expect(WidgetStackRotation.decide(memberIDs: [], relevance: [:], chosenID: nil, chosenAt: nil,
                                           smartRotate: true, now: now) == nil)
    }

    @Test func theMostRelevantWidgetWins() {
        let decision = decide(["music": .ongoing(), "timers": .timely(), "weather": .notYet(until: now.addingTimeInterval(600))])
        #expect(decision?.memberID == "timers")
        // The time the weather has something to say is the next look.
        #expect(decision?.nextCheck == now.addingTimeInterval(600))
        #expect(decide(["music": .ongoing(), "upnext": .needsLook()])?.memberID == "upnext")
    }

    @Test func tiesGoToThePersonsWidgetThenToTheFirst() {
        #expect(decide(["music": .ongoing(), "timers": .ongoing()])?.memberID == "music")
        #expect(decide(["music": .ongoing(), "weather": .ongoing()], chosen: "weather", chosenAt: now.addingTimeInterval(-3600))?
            .memberID == "weather")
    }

    @Test func returnsToThePersonsWidgetWhenItPasses() {
        let earlier = now.addingTimeInterval(-WidgetStackRotation.manualHold * 2)
        // Weather was picked by hand long ago. The timer runs, so Timers shows.
        #expect(decide(["timers": .timely()], chosen: "weather", chosenAt: earlier)?.memberID == "timers")
        // The timer ends: back to Weather, not to the first widget.
        #expect(decide([:], chosen: "weather", chosenAt: earlier)?.memberID == "weather")
    }

    @Test func aFlipByHandHoldsForAWhile() {
        let flipped = now.addingTimeInterval(-60)
        let held = decide(["timers": .timely()], chosen: "music", chosenAt: flipped)
        #expect(held?.memberID == "music")
        #expect(held?.nextCheck == flipped.addingTimeInterval(WidgetStackRotation.manualHold))
        // Once the hold is over, Smart Rotate turns again.
        let later = flipped.addingTimeInterval(WidgetStackRotation.manualHold + 1)
        #expect(decide(["timers": .timely()], chosen: "music", chosenAt: flipped, at: later)?.memberID == "timers")
    }

    @Test func smartRotateOffShowsThePersonsWidget() {
        #expect(decide(["timers": .needsLook()], smartRotate: false)?.memberID == "upnext")
        #expect(decide(["timers": .needsLook()], chosen: "music", smartRotate: false)?.memberID == "music")
    }

    @Test func aWidgetNoLongerInTheStackIsNoOnesChoice() {
        #expect(decide([:], chosen: "gone", chosenAt: now)?.memberID == "upnext")
    }

    @Test func relevanceWithATimeStaysUntilThen() {
        let ring = WidgetRelevance.needsLook(until: now.addingTimeInterval(600))
        let held = WidgetStackRotation.holding(live: ["camera": ring, "music": .ongoing()], held: [:], now: now)
        // Only an answer with a time is kept. Music holds while it plays.
        #expect(held == ["camera": ring])
        // The doorbell's banner closed: the widget says nothing now, but the kept answer stands.
        let standing = WidgetStackRotation.standing(live: [:], held: held, now: now.addingTimeInterval(60))
        #expect(standing["camera"] == ring)
        // Its time passes, and it is gone.
        #expect(WidgetStackRotation.standing(live: [:], held: held, now: now.addingTimeInterval(601)).isEmpty)
        #expect(WidgetStackRotation.holding(live: [:], held: held, now: now.addingTimeInterval(601)).isEmpty)
        // A new answer replaces the kept one.
        #expect(WidgetStackRotation.holding(live: ["camera": .ongoing()], held: held, now: now).isEmpty)
        #expect(WidgetStackRotation.standing(live: ["camera": .ongoing()], held: held, now: now)["camera"] == .ongoing())
    }
}

/// A stack's widgets: how they change, the sizes a stack takes and what a new Smart Stack starts with.
@MainActor @Suite struct WidgetStackTests {
    private func widget(_ id: String, sizes: [WidgetSize] = WidgetSize.standard, relevant: Bool = true) -> WidgetDescriptor {
        var hook: WidgetRelevanceHook?
        if relevant {
            hook = { _ in nil }
        }
        return WidgetDescriptor(id: id, title: id, systemImage: "square", supportedSizes: sizes, relevance: hook) { _ in
            EmptyView()
        }
    }

    @Test func holdsAtMostTen() {
        var stack = WidgetStack.of((0..<9).map { "w\($0)" })
        #expect(!stack.isFull && stack.hasRoom(for: 1) && !stack.hasRoom(for: 2))
        stack.putOnTop([WidgetStack.Member(widgetID: "a"), WidgetStack.Member(widgetID: "b")])
        #expect(stack.members.count == WidgetStack.maxMembers)
        #expect(stack.members.prefix(2).map(\.widgetID) == ["a", "b"])
        stack.append(WidgetStack.Member(widgetID: "c"))
        #expect(stack.members.count == WidgetStack.maxMembers)
        #expect(WidgetStack.of((0..<12).map { "w\($0)" }).members.count == WidgetStack.maxMembers)
    }

    @Test func eachWidgetKeepsItsOwnSettings() throws {
        let list = WidgetSettingKey<String?>("list", default: nil)
        var stack = WidgetStack.of(["personal.reminders", "personal.reminders"])
        var groceries = WidgetSettings()
        groceries[list] = "groceries"
        stack.setSettings(groceries, for: stack.members[1].id)
        stack.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let decoded = try JSONDecoder().decode(WidgetStack.self, from: JSONEncoder().encode(stack))
        #expect(decoded.settings(for: decoded.members[0].id)[list] == "groceries")
        #expect(decoded.settings(for: decoded.members[1].id).isEmpty)
        stack.setSettings(WidgetSettings(), for: stack.members[0].id)
        #expect(stack.members[0].settings == nil)
    }

    @Test func smartRotateReadsAsOnWhenMissing() throws {
        let json = #"{"members":[{"id":"1","widgetID":"a"},{"id":"2","widgetID":"b"}]}"#
        let stack = try JSONDecoder().decode(WidgetStack.self, from: Data(json.utf8))
        #expect(stack.smartRotate)
        #expect(stack.members.map(\.widgetID) == ["a", "b"])
    }

    @Test func aStackTakesTheSizesAllItsWidgetsComeIn() {
        #expect(WidgetStack.sizes(supportedByAll: [WidgetSize.allCases, [.small, .medium], [.medium, .large]]) == [.medium])
        #expect(WidgetStack.sizes(supportedByAll: [[.small], [.large]]).isEmpty)
    }

    @Test func aSmartStackStartsWithWidgetsThatCanSayWhenTheyMatter() {
        let widgets = [
            widget("smarthome.camera"), widget("smarthome.favorites", relevant: false), widget("audio.nowplaying"),
            widget("personal.upnext", sizes: [.small, .medium, .large, .tall]), widget("other.relevant"),
            widget("personal.weather"), widget("shell.homestatus", sizes: [.small, .medium, .large, .tall]),
        ]
        let medium = WidgetStack.suggested(from: widgets, size: .medium).map(\.id)
        #expect(medium == ["personal.upnext", "personal.weather", "audio.nowplaying", "shell.homestatus",
                           "smarthome.camera", "other.relevant"])
        #expect(WidgetStack.suggested(from: widgets, size: .tall).map(\.id) == ["personal.upnext", "shell.homestatus"])
        #expect(WidgetStack.smartStackSizes(from: widgets) == WidgetSize.allCases)
        #expect(WidgetStack.smartStackSizes(from: [widget("a"), widget("b", sizes: [.tall])]).isEmpty)
    }
}
