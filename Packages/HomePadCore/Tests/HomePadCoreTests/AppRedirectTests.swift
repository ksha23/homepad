import SwiftUI
import Testing
@testable import HomePadCore

/// An app ID that moved inside another app keeps opening it, so old deep links
/// (the camera widget, faces, Siri, `homepad://app/cameras`) still land.
@MainActor @Suite struct AppRedirectTests {
    @Test func aRedirectOpensItsAppAfterPreparingIt() {
        let registry = ModuleRegistry()
        registry.register(app: AppDescriptor(id: "home", title: "Home", systemImage: "house", category: .home) { EmptyView() })
        var prepared = 0
        registry.register(redirect: AppRedirect(id: "cameras", opens: "home") { prepared += 1 })
        #expect(registry.followingRedirect("cameras") == "home")
        #expect(prepared == 1)
        // Redirects never become apps, so nothing lists them.
        #expect(registry.app("cameras") == nil)
        #expect(registry.apps.map(\.id) == ["home"])
    }

    @Test func registeredAppsAndUnknownIDsPassThrough() {
        let registry = ModuleRegistry()
        var prepared = false
        registry.register(app: AppDescriptor(id: "cameras", title: "Cameras", systemImage: "video", category: .home) { EmptyView() })
        registry.register(redirect: AppRedirect(id: "cameras", opens: "home") { prepared = true })
        #expect(registry.followingRedirect("cameras") == "cameras", "A real app wins over a redirect")
        #expect(registry.followingRedirect("music") == "music")
        #expect(!prepared)
    }
}
