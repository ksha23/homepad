import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

/// The Faces app reopens on whose faces it showed, for the whole household.
@MainActor @Suite struct FacesAppStateTests {
    @Test func theOwnerFilterIsSharedAndKeepsLoading() throws {
        #expect(FacesAppState.owner.scope == .household)
        #expect(FacesAppState.owner.defaultValue == .household)
        for owner in [FaceOwner.household, .member(UUID())] {
            let data = try JSONEncoder().encode(owner)
            #expect(try JSONDecoder().decode(FaceOwner.self, from: data) == owner)
        }
    }
}
