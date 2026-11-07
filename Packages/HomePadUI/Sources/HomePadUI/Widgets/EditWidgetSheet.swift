import HomePadCore
import SwiftUI

/// Edit Widget, as on iPadOS: one placed widget's own settings beside a live
/// preview of it with them. Each widget on a Home Screen or a face keeps its
/// own settings (`WidgetSettings`), and they apply as they are changed, so
/// the sheet has only its close button. While this HomePad shares its setup
/// with others, Same on All HomePads sits under the preview
/// (`SameOnAllHomePadsSwitch`), so each HomePad can keep its own settings for
/// the widget. It works on the settings alone, so every host gets it.
///
///     EditWidgetSheet(widget: widget, size: .tall, tile: frame.size, settings: $settings)
///
/// Present it page-sized (`.presentationSizing(.page)`). In a wide sheet, as
/// in landscape, the preview sits beside the settings, and in a narrow one above them.
public struct EditWidgetSheet: View {
    private let widget: WidgetDescriptor
    private let size: WidgetSize
    private let tile: CGSize
    @Binding private var settings: WidgetSettings
    private let onBack: (() -> Void)?
    private let backLabel: String
    private let onClose: (() -> Void)?
    @Environment(AppServices.self) private var services

    /// - Parameters:
    ///   - widget: The widget. Its `makeSettingsView` draws the settings.
    ///   - size: Its size where it sits.
    ///   - tile: The size it is drawn at where it sits, so the preview matches it.
    ///   - settings: The placed widget's settings, saved as each one changes.
    ///   - onBack: A back button before the title, for the page pushed from Edit Stack.
    ///   - onClose: What the close button does there: closing the whole sheet, not only the page. Dismisses when nil.
    public init(widget: WidgetDescriptor, size: WidgetSize, tile: CGSize, settings: Binding<WidgetSettings>,
                onBack: (() -> Void)? = nil, backLabel: String = "Back", onClose: (() -> Void)? = nil) {
        self.widget = widget
        self.size = size
        self.tile = tile
        _settings = settings
        self.onBack = onBack
        self.backLabel = backLabel
        self.onClose = onClose
    }

    /// The share of a wide sheet's width the preview takes.
    static var previewShare: CGFloat { 0.4 }

    /// The room Same on All HomePads takes under the preview in a wide sheet,
    /// so a tall widget's preview leaves it on screen.
    static var switchRoom: CGFloat { 180 }

    public var body: some View {
        SheetScreen(widget.title, onBack: onBack, backLabel: backLabel, onClose: onClose) {
            GeometryReader { proxy in
                let inset = Theme.Spacing.l
                if proxy.size.width > proxy.size.height {
                    let column = proxy.size.width * Self.previewShare
                    let room = showsSwitch ? Self.switchRoom : 0
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: Theme.Spacing.l) {
                            preview(fitting: CGSize(width: column - inset * 2, height: proxy.size.height - inset - room))
                            sameOnAllHomePads
                        }
                        .frame(width: column)
                        page
                    }
                } else {
                    VStack(spacing: Theme.Spacing.m) {
                        preview(fitting: CGSize(width: proxy.size.width - inset * 2, height: proxy.size.height * 0.32))
                        sameOnAllHomePads
                        page
                    }
                }
            }
        }
    }

    /// True while paired HomePads share their setup and the widget has settings to share or keep.
    private var showsSwitch: Bool {
        widget.hasSettings
            && SameOnAllHomePadsSwitch.isShown(for: settings, homePadsSharingSetup: services.homePadsSharingSetup)
    }

    @ViewBuilder
    private var sameOnAllHomePads: some View {
        if showsSwitch {
            SameOnAllHomePadsSwitch(settings: $settings)
                .padding(.horizontal, Theme.Spacing.l)
        }
    }

    /// The widget as it sits, scaled down to fit, with the settings as they are now.
    private func preview(fitting box: CGSize) -> some View {
        WidgetPreview(tile: tile, fitting: box) {
            widget.makeView(size).environment(\.widgetSettings, settings)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(widget.title)")
    }

    @ViewBuilder
    private var page: some View {
        if let makeSettingsView = widget.makeSettingsView {
            makeSettingsView($settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("Nothing to Change", systemImage: widget.systemImage,
                                   description: Text("This widget has no settings."))
        }
    }
}
