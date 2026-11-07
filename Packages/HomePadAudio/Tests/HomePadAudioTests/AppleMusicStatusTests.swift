import Foundation
import MusicKit
import Testing
@testable import HomePadAudio

/// MusicKit failures map to one clear status each.
@Suite struct AppleMusicStatusTests {
    @Test func developerTokenFailureMeansTheServiceIsOff() {
        #expect(AppleMusicStatus.classify(MusicTokenRequestError.developerTokenRequestFailed) == .serviceNotEnabled)
    }

    @Test func accountProblemsNeedASubscription() {
        #expect(AppleMusicStatus.classify(MusicTokenRequestError.userNotSignedIn) == .needsSubscription)
        #expect(AppleMusicStatus.classify(MusicTokenRequestError.privacyAcknowledgementRequired) == .needsSubscription)
    }

    @Test func permissionAndNetwork() {
        #expect(AppleMusicStatus.classify(MusicTokenRequestError.permissionDenied) == .notAuthorized(canAsk: false))
        #expect(AppleMusicStatus.classify(URLError(.notConnectedToInternet)) == .offline)
    }

    @Test func everyStatusHasAFix() {
        let all: [AppleMusicStatus] = [.ready, .needsSubscription, .serviceNotEnabled, .notAuthorized(canAsk: true),
                                       .notAuthorized(canAsk: false), .offline]
        for status in all {
            #expect(!status.message.isEmpty)
            #expect(!status.message.contains("—") && !status.message.contains(";"))
        }
        #expect(AppleMusicStatus.ready.canBrowseCatalog)
        #expect(!AppleMusicStatus.serviceNotEnabled.canBrowseCatalog)
    }
}
