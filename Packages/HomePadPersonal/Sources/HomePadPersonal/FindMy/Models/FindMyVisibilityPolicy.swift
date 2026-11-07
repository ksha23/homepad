import Foundation

/// Who may see, and ring, whose devices in Find My and through the assistant.
///
/// - Nobody recognized: nothing. Picking a name in the People switcher is not enough.
/// - A recognized member sees their own devices.
/// - Admins see every device, since they set up Home Assistant, which already
///   shows them all of its trackers.
/// - With "Share Devices with Everyone" on, every recognized member sees every
///   member's devices, as Family Sharing does in Apple's Find My.
/// - Devices that belong to nobody show only to admins. Hidden devices never show.
struct FindMyVisibilityPolicy: Equatable, Sendable {
    /// `PersonalSettings.findMyShareWithEveryone`.
    var shareWithEveryone = false

    func isVisible(_ ownership: FindMyOwnership, to viewer: CalendarViewer) -> Bool {
        guard let me = viewer.unlockedMemberID else { return false }
        let isAdmin = viewer.adminIDs.contains(me)
        switch ownership {
        case .hidden: return false
        case .nobody: return isAdmin
        case .member(let owner): return owner == me || isAdmin || shareWithEveryone
        }
    }
}
