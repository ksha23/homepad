#if DEBUG
import Foundation

/// Launch arguments for checking phone calendars between two simulators,
/// after pairing and linking them (see `ApprovalDebug`). Debug builds only.
/// The simulators have no Bluetooth, so the HomePad reaches the phone only
/// while its app is open, over the peer link.
///
///     -ConnectShareCalendars YES        iPhone: shares every calendar and list once linked to a HomePad
///     -ConnectPhoneCalendarsDemo YES    iPhone: made-up calendars and lists instead of the simulator's empty ones
@MainActor
enum PhoneCalendarsDebug {
    static func start(_ runtime: ConnectRuntime) {
        guard !runtime.isHomePad, UserDefaults.standard.bool(forKey: "ConnectShareCalendars") else { return }
        Task { await share(runtime) }
    }

    /// Waits up to two minutes for a HomePad this phone is linked to, then shares everything with it.
    private static func share(_ runtime: ConnectRuntime) async {
        for _ in 0..<120 {
            if let pad = runtime.link.homePads.first(where: { runtime.approvals.linkedMember(on: $0.id) != nil }) {
                // The HomePad's key arrives with its link state.
                await runtime.approvals.requestState(of: pad.id)
                try? await Task.sleep(for: .seconds(1))
                let server = runtime.calendarSharing
                await server.requestAccess(to: .calendars, for: pad.id)
                await server.requestAccess(to: .reminders, for: pad.id)
                for calendar in server.calendars where !server.isShared(calendar.id, with: pad.id) {
                    await server.setShared(true, calendar, kind: .calendars, with: pad.id)
                }
                for list in server.lists where !server.isShared(list.id, with: pad.id) {
                    await server.setShared(true, list, kind: .reminders, with: pad.id)
                }
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
