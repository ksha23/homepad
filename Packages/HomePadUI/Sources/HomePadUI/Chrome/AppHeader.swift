import SwiftUI

/// The header row of an app screen. The leading half holds an optional back
/// button, the big title and a title accessory (a view picker). The trailing
/// half holds the toolbar and the close button. The center stays empty for the
/// Now Playing pill (`Theme.Size.nowPlayingZone`). `AppScreen` draws it for
/// you. Use it directly only for a screen that lays out its own content, such
/// as a tool pushed inside an app.
///
///     AppHeader("Security Camera", onBack: { path.removeAll() }, backLabel: "Camera Lab")
///         .padding([.horizontal, .top], Theme.Spacing.l)
///
/// Every item is `Theme.Size.toolbarItem` tall. When a side runs out of room it
/// degrades like an iPadOS toolbar: titles of buttons with a symbol become the
/// symbol, then items move into a More menu (low priority first), and the title
/// shrinks a little before it is cut off. Nothing ever moves into the center.
///
/// When `onClose` is nil and the shell hosts the screen, the close button
/// uses the shell's `\.closeApp` action and tells the shell not to draw its own.
/// An app opened from another app also gets a back button named after it
/// ("Music"), unless `onBack` is set.
public struct AppHeader<TitleAccessory: View, Accessory: View>: View {
    @Environment(\.closeApp) private var closeApp
    @Environment(\.showsAppCloseButton) private var showsAppCloseButton
    private let title: String
    private let onBack: (() -> Void)?
    private let backLabel: String
    private let onClose: (() -> Void)?
    private let titleAccessory: TitleAccessory
    private let accessory: Accessory

    /// - Parameters:
    ///   - title: The screen title, drawn in `Font.screenTitle`. Empty for a
    ///     full-bleed screen that shows its title elsewhere, such as the recipe card.
    ///   - onBack: Shows a back button before the title. Nil hides it.
    ///   - backLabel: What VoiceOver reads for the back button, usually the previous screen's name.
    ///   - onClose: Overrides the shell's close action. Leave nil inside HomePad.
    ///   - accessory: The toolbar before the close button: `GlassIconButton`s,
    ///     `GlassCapsuleButton`s, `HeaderMenu`s and `ToolbarGroup`s, without a stack around them.
    ///   - titleAccessory: Controls right after the title that change what the
    ///     screen shows, such as a `HeaderPicker` for Day, Week and Month.
    public init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back", onClose: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder titleAccessory: () -> TitleAccessory
    ) {
        self.title = title
        self.onBack = onBack
        self.backLabel = backLabel
        self.onClose = onClose
        self.titleAccessory = titleAccessory()
        self.accessory = accessory()
    }

    public var body: some View {
        HeaderRow {
            HeaderLeading(title: title) { backButton } titleAccessory: { titleAccessory }
        } trailing: {
            HeaderTrailing(items: accessory, close: drawnClose.map { CloseButton(action: $0) })
        }
        .dynamicTypeSize(...ToolbarMetrics.largestTypeSize)
        // Also while the button is hidden, so the shell does not add its own.
        .preference(key: AppDrawsCloseButtonKey.self, value: resolvedClose != nil)
    }

    /// `onBack`, or a button back to the app that opened this one ("Music").
    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            GlassIconButton("chevron.left", label: backLabel, action: onBack)
        } else if onClose == nil, let closeApp, let title = closeApp.backTitle {
            GlassCapsuleButton(title, systemImage: "chevron.left") { closeApp.goBack() }
                .accessibilityLabel("Back to \(title)")
        }
    }

    private var resolvedClose: (() -> Void)? {
        if let onClose { return onClose }
        guard let closeApp else { return nil }
        return { closeApp() }
    }

    /// The shell's close button shows only with Show Close Buttons on. A close
    /// passed in (`onClose`) always shows.
    private var drawnClose: (() -> Void)? {
        onClose == nil && !showsAppCloseButton ? nil : resolvedClose
    }
}

public extension AppHeader where TitleAccessory == EmptyView {
    /// A header without a title accessory. A lone trailing closure is the
    /// toolbar. With two defaulted closures, Swift 5 would hand it to the last
    /// one, the title accessory, so this initializer has only the toolbar.
    ///
    ///     AppHeader("Now Playing") { GlassIconButton("list.bullet", label: "Up Next") { showQueue() } }
    init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back", onClose: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.init(title, onBack: onBack, backLabel: backLabel, onClose: onClose, accessory: accessory, titleAccessory: { EmptyView() })
    }
}
