import Testing
@testable import HomePadCore

/// Modules describe their screens to the assistant through the registry.
@MainActor @Suite struct ScreenContextProviderTests {
    @Test func anAppProviderIsKeyedByItsApp() {
        let provider = ScreenContextProvider(appID: "recipes") { "The recipe card for Shakshuka." }
        #expect(provider.id == "recipes")
        #expect(provider.appID == "recipes")
        #expect(!provider.isPersonal)
        #expect(provider.summary() == "The recipe card for Shakshuka.")
    }

    @Test func registeringTheSameIDReplacesTheOldProvider() {
        let registry = ModuleRegistry()
        registry.register(screenContext: ScreenContextProvider(appID: "recipes") { "old" })
        registry.register(screenContext: ScreenContextProvider(id: "doorbell", appID: nil) { nil })
        registry.register(screenContext: ScreenContextProvider(appID: "recipes") { "new" })
        #expect(registry.screenContexts.count == 2)
        #expect(registry.screenContexts.first { $0.id == "recipes" }?.summary() == "new")
        #expect(registry.screenContexts.first { $0.id == "doorbell" }?.appID == nil)
    }
}
