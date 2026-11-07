import SwiftUI

/// Standard chrome for an app screen: the header row (title, toolbar, close
/// button) and the content. Every app uses it so every screen feels the same.
///
/// When `onClose` is nil and the shell hosts the screen, the close button
/// uses the shell's `\.closeApp` action, so apps never need to wire it up.
/// Put actions in `accessory` and a view picker in `titleAccessory`. See
/// `AppHeader` for how the header fits them around the Now Playing pill.
///
///     AppScreen("Timers") {
///         GlassIconButton("plus", label: "New Timer") { compose() }
///     } content: {
///         TimerList()
///     }
public struct AppScreen<Content: View, TitleAccessory: View, Accessory: View>: View {
    private let title: String
    private let onBack: (() -> Void)?
    private let backLabel: String
    private let onClose: (() -> Void)?
    private let titleAccessory: TitleAccessory
    private let accessory: Accessory
    private let content: Content

    /// - Parameters:
    ///   - title: The screen title, drawn in `Font.screenTitle`.
    ///   - onBack: Shows a back button before the title, for a screen pushed inside an app.
    ///   - backLabel: What VoiceOver reads for the back button, usually the previous screen's name.
    ///   - onClose: Overrides the shell's close action. Leave nil inside HomePad.
    ///   - accessory: The toolbar before the close button.
    ///   - titleAccessory: Controls right after the title, such as a `HeaderPicker`.
    ///   - content: The screen's content.
    public init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back", onClose: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder titleAccessory: () -> TitleAccessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onBack = onBack
        self.backLabel = backLabel
        self.onClose = onClose
        self.titleAccessory = titleAccessory()
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            AppHeader(title, onBack: onBack, backLabel: backLabel, onClose: onClose) {
                accessory
            } titleAccessory: {
                titleAccessory
            }
            content
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
