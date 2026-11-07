#if DEBUG
import Foundation

/// Pairs two simulators through the real pairing flow, with no typing. Debug
/// builds only, and only with a launch argument on each side:
///
///     -ConnectPairingCode 123456   on the HomePad: shows this code at launch
///     -ConnectJoinCode 123456      on an iPhone, or a second HomePad: joins the first HomePad showing a code
///     -ConnectJoinHomePad Kitchen  with -ConnectJoinCode: joins only the HomePad of that room,
///                                  so simulators of other checkouts on this Mac, on the same network, are left alone
///
/// One simulator can also act as if it shared its setup, to see what that
/// shows, such as Same on All HomePads on Edit Widget:
///
///     -ConnectDemoSyncedHomePads 2 on the HomePad: counts as synced with that many HomePads
@MainActor
enum DebugPairing {
    static func start(_ runtime: ConnectRuntime) {
        let defaults = UserDefaults.standard
        if runtime.isHomePad, let code = defaults.string(forKey: "ConnectPairingCode").flatMap(PairingCode.normalize) {
            // Re-advertising while the listener still registers with Bonjour
            // failed it ("ServiceNotRunning"), so the code shows once it is up.
            Task {
                try? await Task.sleep(for: .seconds(3))
                runtime.link.openPairingWindow(PairingWindow(code: code))
            }
        }
        if let code = defaults.string(forKey: "ConnectJoinCode").flatMap(PairingCode.normalize) {
            Task { await join(runtime.link, code: code) }
        }
        if runtime.isHomePad, defaults.object(forKey: "ConnectDemoSyncedHomePads") != nil {
            runtime.services.homePadsSharingSetup = defaults.integer(forKey: "ConnectDemoSyncedHomePads")
        }
    }

    /// Waits up to a minute for a HomePad that shows a code, then joins it.
    private static func join(_ link: PeerLink, code: String) async {
        let room = UserDefaults.standard.string(forKey: "ConnectJoinHomePad")
        for _ in 0..<60 where link.household == nil {
            if let host = link.pairableHomePads.first(where: { room == nil || $0.name == room }) {
                try? await link.join(host.id, code: code)
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
