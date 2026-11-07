import Testing
@testable import HomePadKitchen

@MainActor
@Suite struct KitchenModuleTests {
    @Test func moduleHasID() {
        #expect(KitchenModule.id == "kitchen")
    }
}
