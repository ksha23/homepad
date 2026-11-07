#if DEBUG
import Foundation

/// Launch arguments for checking Apple Music sharing between two simulators,
/// after pairing and linking them (see `ApprovalDebug`). Debug builds only.
/// MusicKit cannot sign in on a simulator, so the phone sends a made-up token.
///
///     -ConnectShareAppleMusic YES    iPhone: turns on Use My Apple Music once linked to a HomePad
///     -ConnectAppleMusicDemo YES     iPhone: a made-up token instead of MusicKit's
@MainActor
enum AppleMusicDebug {
    static func start(_ runtime: ConnectRuntime) {
        guard !runtime.isHomePad, UserDefaults.standard.bool(forKey: "ConnectShareAppleMusic") else { return }
        Task { await share(runtime) }
    }

    /// Waits up to two minutes for a HomePad this phone is linked to, then shares with it.
    private static func share(_ runtime: ConnectRuntime) async {
        for _ in 0..<120 {
            if let pad = runtime.link.homePads.first(where: { runtime.approvals.linkedMember(on: $0.id) != nil }) {
                // The HomePad's key arrives with its link state.
                await runtime.approvals.requestState(of: pad.id)
                try? await Task.sleep(for: .seconds(1))
                if !runtime.appleMusicSharing.isSharing(with: pad.id) {
                    await runtime.appleMusicSharing.setSharing(true, with: pad.id)
                }
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
