import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

/// The Assistant app reopens on each person's tab, and on Settings only for
/// someone who may change them.
@MainActor
@Suite struct AssistantAppStateTests {
    @Test func theTabIsKeptPerPerson() {
        #expect(AssistantAppState.tab.scope == .member)
        #expect(AssistantAppState.tab.defaultValue == .chat)
    }

    @Test func settingsReopenOnlyForSomeoneWhoMayChangeThem() {
        #expect(AssistantAppState.restoredTab(.settings, canChangeSettings: true) == .settings)
        #expect(AssistantAppState.restoredTab(.settings, canChangeSettings: false) == .chat)
        #expect(AssistantAppState.restoredTab(.chat, canChangeSettings: false) == .chat)
    }
}
