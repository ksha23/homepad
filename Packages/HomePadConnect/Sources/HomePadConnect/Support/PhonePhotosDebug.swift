#if DEBUG
import Foundation

/// Launch arguments for checking phone photos between two simulators, after
/// pairing and linking them (see `ApprovalDebug`). Debug builds only. The
/// simulators have no Bluetooth, so the HomePad reaches the phone only while
/// its app is open, over the peer link.
///
///     -ConnectSharePhotos YES        iPhone: turns on Show My Photos once linked to a HomePad
///     -ConnectPhonePhotosDemo YES    iPhone: serves made-up photos instead of the simulator's library
@MainActor
enum PhonePhotosDebug {
    static func start(_ runtime: ConnectRuntime) {
        guard !runtime.isHomePad, UserDefaults.standard.bool(forKey: "ConnectSharePhotos") else { return }
        Task { await share(runtime) }
    }

    /// Waits up to two minutes for a HomePad this phone is linked to, then shares with it.
    private static func share(_ runtime: ConnectRuntime) async {
        for _ in 0..<120 {
            if let pad = runtime.link.homePads.first(where: { runtime.approvals.linkedMember(on: $0.id) != nil }) {
                // The HomePad's key arrives with its link state.
                await runtime.approvals.requestState(of: pad.id)
                try? await Task.sleep(for: .seconds(1))
                if !runtime.photoSharing.isSharing(with: pad.id) {
                    await runtime.photoSharing.setSharing(true, with: pad.id)
                }
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
