import SwiftUI

/// HomePad on Apple Watch: intercom push to talk, a timers glance and scene buttons.
/// It talks only to the paired iPhone, which relays to HomePads.
@main
struct HomePadWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            TabView {
                WatchIntercomView()
                WatchTimersView()
                WatchScenesView()
            }
            .tabViewStyle(.verticalPage)
            .environment(link)
            .task { link.activate() }
        }
    }
}
