import Testing
@testable import HomePadConnect

/// Which session two devices keep when both dial each other at once.
@Suite struct PeerLinkSessionTests {
    private let pad = "A-pad"
    private let phone = "B-phone"

    /// What one device keeps, given which of the two sessions opened first there.
    private func kept(on local: String, remote: String, firstDialedByLocal: Bool) -> String {
        let keepsSecond = PeerLink.keepsNewSession(
            newIsInitiator: !firstDialedByLocal, oldIsInitiator: firstDialedByLocal, local: local, remote: remote
        )
        let localDialedKept = keepsSecond ? !firstDialedByLocal : firstDialedByLocal
        return localDialedKept ? local : remote
    }

    @Test func bothDevicesKeepTheSessionTheLowerIDDialed() {
        for padSawItsOwnFirst in [true, false] {
            for phoneSawItsOwnFirst in [true, false] {
                let padKeeps = kept(on: pad, remote: phone, firstDialedByLocal: padSawItsOwnFirst)
                let phoneKeeps = kept(on: phone, remote: pad, firstDialedByLocal: phoneSawItsOwnFirst)
                #expect(padKeeps == pad)
                #expect(phoneKeeps == pad)
            }
        }
    }

    @Test func aReconnectFromTheSameDeviceReplacesTheOldSession() {
        #expect(PeerLink.keepsNewSession(newIsInitiator: true, oldIsInitiator: true, local: phone, remote: pad))
        #expect(PeerLink.keepsNewSession(newIsInitiator: false, oldIsInitiator: false, local: pad, remote: phone))
    }
}
