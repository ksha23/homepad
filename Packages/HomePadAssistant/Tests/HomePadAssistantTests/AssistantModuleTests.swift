import Testing
@testable import HomePadAssistant

@Suite struct AssistantModuleTests {
    @Test @MainActor func moduleHasID() {
        #expect(AssistantModule.id == "assistant")
    }
}
