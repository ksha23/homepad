import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The one way HomePad asks for a permission: a friendly explanation before
/// the system prompt, and a way to the Settings app once someone said no.
///
/// `.page` fills a screen like `EmptyStateView`. `.row` fits in a `Form` section.
///
///     PermissionPrompt(feature: "Calendar", systemImage: "calendar",
///                      reason: "See the household's events on this HomePad.",
///                      isDenied: calendar.isDenied) { await calendar.requestAccess() }
///
///     PermissionPrompt("Hear Alarms and Doorbells", message: "Audio is analyzed on this iPad.",
///                      systemImage: "mic.fill", state: .ask, style: .row) { await requestMic() }
public struct PermissionPrompt: View {
    /// Whether HomePad still has to ask, or the person already said no.
    public enum State: Sendable {
        /// Not asked yet. The button reads "Continue" and runs `request`.
        case ask
        /// Denied. The button reads "Open Settings" and opens HomePad's page in the Settings app.
        case denied
    }

    /// Where the prompt sits.
    public enum Style: Sendable {
        /// Centered on a screen, like `EmptyStateView`.
        case page
        /// A row inside a `Form` section.
        case row
    }

    private let title: String
    private let message: String
    private let systemImage: String
    private let state: State
    private let style: Style
    private let request: () async -> Void
    @Environment(\.openURL) private var openURL

    /// - Parameters:
    ///   - title: A short headline.
    ///   - message: What access makes possible and how private it is.
    ///   - systemImage: SF Symbol for the feature.
    ///   - state: `.ask` or `.denied`.
    ///   - style: `.page` or `.row`.
    ///   - request: Asks iPadOS for access. Only called in the `.ask` state.
    public init(
        _ title: String, message: String, systemImage: String, state: State, style: Style = .page,
        request: @escaping () async -> Void = {}
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.state = state
        self.style = style
        self.request = request
    }

    /// Builds the standard wording for a feature: "Show Calendar on HomePad"
    /// before asking and "Calendar Access Is Off" after a no.
    ///
    /// - Parameters:
    ///   - feature: The feature's name, such as "Calendar" or "Photos".
    ///   - systemImage: SF Symbol for the feature.
    ///   - reason: One or two friendly sentences about what access makes possible
    ///     and how private it is.
    ///   - isDenied: True once the person said no.
    ///   - style: `.page` or `.row`.
    ///   - request: Asks iPadOS for access.
    public init(
        feature: String, systemImage: String, reason: String, isDenied: Bool, style: Style = .page,
        request: @escaping () async -> Void
    ) {
        if isDenied {
            self.init("\(feature) Access Is Off",
                      message: "\(reason) Turn on access for HomePad in the Settings app, then come back.",
                      systemImage: systemImage, state: .denied, style: style, request: request)
        } else {
            self.init("Show \(feature) on HomePad",
                      message: "\(reason) HomePad asks iPadOS for access next.",
                      systemImage: systemImage, state: .ask, style: style, request: request)
        }
    }

    public var body: some View {
        switch style {
        case .page:
            EmptyStateView(title, message: message, systemImage: systemImage, actionTitle: actionTitle, action: perform)
        case .row:
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title).font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    GlassCapsuleButton(actionTitle, size: .regular, isProminent: true, action: perform)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private var actionTitle: String {
        state == .ask ? "Continue" : "Open Settings"
    }

    private func perform() {
        switch state {
        case .ask:
            Task { await request() }
        case .denied:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            #endif
        }
    }
}
