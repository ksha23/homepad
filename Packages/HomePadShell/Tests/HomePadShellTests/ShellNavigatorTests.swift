import Foundation
import HomePadCore
import HomePadUI
import SwiftUI
import Testing
@testable import HomePadShell

@MainActor
@Suite struct ShellNavigatorTests {
    private let registry = ModuleRegistry()
    private let household: Household
    private let navigator: ShellNavigator

    init() {
        let defaults = UserDefaults(suiteName: "homepad.shell.nav.\(UUID().uuidString)")!
        household = Household(store: SettingsStore(defaults: defaults))
        registry.register(app: AppDescriptor(id: "music", title: "Music", systemImage: "music.note", category: .media) { EmptyView() })
        registry.register(app: AppDescriptor(
            id: "messages", title: "Messages", systemImage: "message", category: .communication, requiresRecognizedMember: true
        ) { EmptyView() })
        navigator = ShellNavigator(registry: registry, household: household)
    }

    @Test func opensSharedAppsDirectly() {
        navigator.open(appID: "music")
        #expect(navigator.screen == .app("music"))
        #expect(navigator.gatedAppID == nil)
    }

    /// The Cameras app moved into Home. Its ID still opens Home, on the cameras.
    @Test func aRedirectedIDOpensTheAppItNames() {
        var prepared = false
        registry.register(redirect: AppRedirect(id: "cameras", opens: "music") { prepared = true })
        navigator.open(appID: "cameras")
        #expect(navigator.screen == .app("music"))
        #expect(prepared)
    }

    @Test func goingBackReturnsToTheAppThatOpenedIt() {
        registerNowPlaying()
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        #expect(navigator.returnAppID == "music")
        navigator.goBack()
        #expect(navigator.screen == .app("music"))
        #expect(navigator.returnAppID == nil)
    }

    @Test func openingTheAppToGoBackToNeverBounces() {
        registerNowPlaying()
        navigator.goHome()
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        navigator.open(appID: "music")
        #expect(navigator.returnAppID == nil)
        navigator.goBack()
        #expect(navigator.screen == .home)
    }

    @Test func homeForgetsTheAppToGoBackTo() {
        registerNowPlaying()
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        navigator.goHome()
        #expect(navigator.returnAppID == nil)
        navigator.open(appID: "nowplaying")
        #expect(navigator.returnAppID == nil)
    }

    private func registerNowPlaying() {
        registry.register(app: AppDescriptor(
            id: "nowplaying", title: "Now Playing", systemImage: "play", category: .media, presentsOverOpener: true
        ) { EmptyView() })
    }

    /// Now Playing shows over the app that opened it, which stays alive
    /// underneath until it comes back on top or Home is shown.
    @Test func theOpenerStaysAliveUnderAnAppThatPresentsOverIt() {
        registerNowPlaying()
        navigator.open(appID: "music")
        #expect(navigator.appBehindID == nil)
        navigator.open(appID: "nowplaying")
        #expect(navigator.appBehindID == "music")
        navigator.goBack()
        #expect(navigator.screen == .app("music"))
        #expect(navigator.appBehindID == nil)
    }

    @Test func homeAndTheFaceDropTheAppBehind() {
        registerNowPlaying()
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        navigator.goHome()
        #expect(navigator.appBehindID == nil)
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        navigator.goAmbient()
        #expect(navigator.appBehindID == nil)
    }

    /// Opened from the Home Screen there is nothing to keep, and an ordinary
    /// app opened from another one replaces it as before.
    @Test func onlyAnOpenerUnderAPresentingAppIsKept() {
        registerNowPlaying()
        navigator.goHome()
        navigator.open(appID: "nowplaying")
        #expect(navigator.appBehindID == nil)
        navigator.open(appID: "music")
        #expect(navigator.appBehindID == nil, "Music does not present over Now Playing")
    }

    /// An app using a camera (Mirror) is not kept out of sight, so the camera stops.
    @Test func anOpenerHoldingACameraIsNotKept() {
        registerNowPlaying()
        navigator.mayKeepAppBehind = { _ in false }
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        #expect(navigator.appBehindID == nil)
        #expect(navigator.returnAppID == "music", "going back still returns to it")
    }

    /// Opening the app underneath brings it back on top instead of keeping a second copy.
    @Test func openingTheAppBehindBringsItBack() {
        registerNowPlaying()
        navigator.open(appID: "music")
        navigator.open(appID: "nowplaying")
        navigator.open(appID: "music")
        #expect(navigator.screen == .app("music"))
        #expect(navigator.appBehindID == nil)
    }

    @Test func personalAppsWaitBehindTheGateUntilRecognized() {
        let member = HouseholdMember(name: "Margot")
        household.add(member)
        household.select(member.id)
        navigator.open(appID: "messages")
        #expect(navigator.gatedAppID == "messages")
        #expect(navigator.screen == .home)
        household.recognize(member.id)
        navigator.completeGate()
        #expect(navigator.screen == .app("messages"))
        #expect(navigator.gatedAppID == nil)
    }

    @Test func recognizedMembersSkipTheGate() {
        let member = HouseholdMember(name: "Margot")
        household.add(member)
        household.recognize(member.id)
        navigator.open(appID: "messages")
        #expect(navigator.screen == .app("messages"))
    }

    @Test func relockingPutsTheGateBackUp() {
        let member = HouseholdMember(name: "Margot")
        household.add(member)
        household.recognize(member.id)
        navigator.open(appID: "messages")
        household.select(nil)
        navigator.relockIfNeeded()
        #expect(navigator.screen == .home)
        #expect(navigator.gatedAppID == "messages")
    }

    /// The assistant hears which app is on screen, and nothing while a personal
    /// app waits behind the gate.
    @Test func reportsTheAppOnScreen() {
        var reported: [String?] = []
        navigator.onOpenAppChange = { reported.append($0) }
        navigator.open(appID: "music")
        navigator.open(appID: "music")
        navigator.goHome()
        navigator.open(appID: "messages")
        navigator.goAmbient()
        #expect(reported == ["music", nil])
    }

    @Test func unknownAppsStillOpenAFriendlyScreen() {
        navigator.open(appID: "dashboards")
        #expect(navigator.screen == .app("dashboards"))
    }

    @Test func swipeUpGoesHomeThenTogglesTheAppGrid() {
        navigator.goHome()
        navigator.open(appID: "music")
        navigator.swipeUpFromBottom()
        #expect(navigator.screen == .home)
        navigator.swipeUpFromBottom()
        #expect(navigator.panel == .appGrid)
        navigator.swipeUpFromBottom()
        #expect(navigator.panel == nil)
    }

    /// An app grows out of the smallest source under the touch that opened it, however it was asked to
    /// open. Opened from the face it still closes to the Home Screen. With nothing under the touch (a link,
    /// VoiceOver) it comes from its icon.
    @Test func anAppOpensFromWhatWasTouchedAndClosesToTheHomeScreen() {
        let widget = ZoomSource(frame: CGRect(x: 40, y: 60, width: 320, height: 150), shape: .surface(cornerRadius: 28))
        let pill = ZoomSource(frame: CGRect(x: 60, y: 160, width: 44, height: 44), shape: .capsule)
        navigator.windowSources = ["faceWidget/a": widget, "pill/timers": pill]
        navigator.noteTouch(at: CGPoint(x: 70, y: 170))
        navigator.open(appID: "music")
        #expect(navigator.zoomOrigins["music"]?.id == "pill/timers")
        navigator.swipeUpFromBottom()
        #expect(navigator.screen == .home)

        navigator.homeSources = ["music": ZoomSource(frame: CGRect(x: 500, y: 300, width: 100, height: 100), shape: .icon)]

        navigator.noteTouch(at: CGPoint(x: 900, y: 700))
        navigator.open(appID: "music")
        #expect(navigator.zoomOrigins["music"]?.id == "music")
        navigator.closeApp()
        #expect(navigator.screen == .home)
    }

    /// Holding the face opens Faces, which closes back to the face, by a tap on the home bar or a swipe.
    @Test func facesOpenedByHoldingTheFaceClosesBackToIt() {
        navigator.open(appID: "faces", fromFace: true)
        navigator.swipeUpFromBottom()
        #expect(navigator.screen == .ambient)
    }

    /// A touch on a widget's name, under its tile, opens the app out of the widget, which it lands on.
    @Test func aWidgetsNameCountsAsTheWidget() {
        navigator.goHome()
        let tile = CGRect(x: 64, y: 152, width: 339, height: 374)
        let widget = ZoomSource(frame: tile, shape: .surface(cornerRadius: 28),
                                hitFrame: CGRect(x: 64, y: 152, width: 339, height: 374 + 44))
        navigator.homeSources = ["widget/favorites": widget,
                                 "home": ZoomSource(frame: CGRect(x: 500, y: 600, width: 93, height: 93), shape: .icon)]
        navigator.noteTouch(at: CGPoint(x: 253, y: 536))
        navigator.open(appID: "music")
        #expect(navigator.zoomOrigins["music"]?.id == "widget/favorites")
        #expect(navigator.zoomOrigins["music"]?.source.frame == tile)
    }

    /// Control Center's tiles are not sources, and the face under it was not touched.
    @Test func aPanelOverTheFaceIsNotWhereAnAppOpensFrom() {
        let widget = ZoomSource(frame: CGRect(x: 0, y: 0, width: 300, height: 300), shape: .surface(cornerRadius: 28))
        navigator.windowSources = ["faceWidget/a": widget]
        navigator.toggle(.controlCenter)
        navigator.noteTouch(at: CGPoint(x: 10, y: 10))
        navigator.open(appID: "music")
        #expect(navigator.zoomOrigins["music"] == nil)
    }

    @Test func showFaceGoesAmbientAndClosesPanels() {
        navigator.goHome()
        navigator.toggle(.controlCenter)
        navigator.showFace("faces.photos")
        #expect(navigator.screen == .ambient)
        #expect(navigator.panel == nil)
        #expect(navigator.faceOverride == "faces.photos")
    }

    @Test func openSettingsRemembersThePane() {
        navigator.openSettings(pane: "kiosk")
        #expect(navigator.screen == .app("settings"))
        #expect(navigator.pendingSettingsPane == "kiosk")
    }

    @Test func personalAccessLevels() {
        #expect(PersonalAccess(household) == .guest)
        let member = HouseholdMember(name: "Margot")
        household.add(member)
        household.select(member.id)
        #expect(PersonalAccess(household) == .selected)
        #expect(PersonalAccess.selected.visibility(isPersonal: true) == .locked)
        #expect(PersonalAccess.guest.visibility(isPersonal: true) == .hidden)
        #expect(PersonalAccess.guest.visibility(isPersonal: false) == .visible)
        household.recognize(member.id)
        #expect(PersonalAccess(household) == .unlocked)
    }
}
