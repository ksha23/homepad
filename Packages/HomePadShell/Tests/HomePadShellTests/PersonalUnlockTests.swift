import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

/// Personal widgets such as Up Next stay unlocked while the recognized person
/// keeps using the screen, and the iPad goes back to Guest once they stop.
@MainActor
@Suite struct PersonalUnlockTests {
    let kyle = HouseholdMember(name: "Kyle", isAdmin: true)

    private func unlockedKiosk() -> KioskHarness {
        let kiosk = KioskHarness()
        kiosk.services.household.add(kyle)
        kiosk.controller.start()
        // Face ID through the recognition gate: one recognition, no camera refreshes after it.
        kiosk.services.household.recognize(kyle.id, now: kiosk.clock.now)
        return kiosk
    }

    private func upNextIsLocked(_ kiosk: KioskHarness) -> Bool {
        PersonalAccess(kiosk.services.household).visibility(isPersonal: true) == .locked
    }

    @Test func touchesKeepUpNextUnlockedPastTheWindow() {
        let kiosk = unlockedKiosk()
        let window = kiosk.services.household.unlockWindow
        for _ in 0..<5 {
            kiosk.advance(window / 2)
            kiosk.controller.noteTouch()
        }
        kiosk.advance(window / 2)
        #expect(!upNextIsLocked(kiosk))
        #expect(PersonalAccess(kiosk.services.household) == .unlocked)
    }

    @Test func backToGuestOnceNobodyTouchesForTheWindow() {
        let kiosk = unlockedKiosk()
        let window = kiosk.services.household.unlockWindow
        kiosk.advance(window - 1)
        kiosk.controller.noteTouch()
        kiosk.advance(window + 1)
        // The profile leaves with the unlock: Guest, where Up Next is hidden.
        #expect(PersonalAccess(kiosk.services.household) == .guest)
        // Touching the Guest screen does not bring Kyle back.
        kiosk.controller.noteTouch()
        kiosk.advance(1)
        #expect(PersonalAccess(kiosk.services.household) == .guest)
    }
}
