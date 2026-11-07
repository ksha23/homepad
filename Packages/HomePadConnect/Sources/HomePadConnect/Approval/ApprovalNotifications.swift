import Foundation
import UIKit
import UserNotifications

/// Shows and takes away the system notification for an approval request.
@MainActor
protocol ApprovalNotifying {
    func show(_ prompt: ApprovalResponder.Prompt)
    func remove(_ id: UUID)
}

/// A local notification while the companion is not in front. Tapping it
/// opens the app, where the prompt waits. In front the sheet is enough.
///
/// This reaches the phone only while the app still runs, such as just after
/// it went to the background. A closed or suspended app has no session, so
/// the HomePad cannot reach it without push notifications (APNs).
struct ApprovalNotifications: ApprovalNotifying {
    func show(_ prompt: ApprovalResponder.Prompt) {
        guard UIApplication.shared.applicationState != .active else { return }
        let request = prompt.request
        let content = UNMutableNotificationContent()
        content.title = "Unlock \(request.appTitle) on \(request.homePadName)?"
        content.body = "Open HomePad to approve with Face ID or your passcode."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "homepad.approvals"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.identifier(request.id), content: content, trigger: nil)
        )
    }

    func remove(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(id)])
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(id)])
    }

    private static func identifier(_ id: UUID) -> String { "homepad.approval.\(id.uuidString)" }
}
