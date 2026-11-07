import SwiftUI

/// Shown where a feature needs setup, has no data yet, or lacks a permission
/// (see `PermissionPrompt` for the permission wording). Wraps the system
/// `ContentUnavailableView` and offers at most one action.
///
///     EmptyStateView("No Timers", message: "Say \"Set a timer for 10 minutes\".",
///                    systemImage: "timer")
public struct EmptyStateView: View {
    private let title: String
    private let message: String
    private let systemImage: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: A short headline.
    ///   - message: One or two plain sentences.
    ///   - systemImage: SF Symbol over the title.
    ///   - actionTitle: Title of the one prominent button, if any.
    ///   - action: Called when the button is tapped.
    public init(_ title: String, message: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        // The title a size up from the system's Title 3, so the one line that
        // says what is missing reads from arm's length. The message is Title 3.
        ContentUnavailableView {
            Label {
                Text(title).font(.title.bold())
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(message).font(.title3)
        } actions: {
            if let actionTitle, let action {
                GlassCapsuleButton(actionTitle, isProminent: true, action: action)
            }
        }
    }
}
