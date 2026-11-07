import Testing
@testable import HomePadAudio

@MainActor @Suite struct AudioModuleTests {
    @Test func moduleHasID() {
        #expect(AudioModule.id == "audio")
    }
}
