import SwiftUI

/// The header of a sheet: the title on the leading side, and on the trailing
/// side the sheet's toolbar and the round glass close button. It is the same
/// row as an app's header (`AppHeader`), with the same item size, the same
/// toolbar stages and one prominent action at most, so a sheet reads like
/// every other screen. There are no Cancel and Done corners: closing is the
/// close button, and the action that commits the sheet (Post, Add, Save) is
/// the prominent toolbar item next to it.
///
///     SheetHeader("New Note") {
///         GlassCapsuleButton("Post", isProminent: true, action: post).disabled(text.isEmpty)
///     }
///
/// The Now Playing pill never covers a sheet, since UIKit presents sheets
/// above the shell that draws it. So the row keeps no zone for it, and its
/// sides are `Theme.Spacing.l` apart (`HeaderSplit.sheet`). The toolbar
/// takes what the title leaves, so a short title leaves room for "Add 3 to
/// Groceries". A long title keeps 60 percent and shrinks, and the toolbar
/// never gets less than the 160 points Post and the close button take. A
/// sheet with only the close button gives the title all but that button.
/// The title is measured on its own, so the split never depends on the
/// sides, and each side still has a fixed width: the toolbar stages are
/// measured at one width, as in every header.
///
/// Closing calls `onClose`, or dismisses the sheet when it is nil. In a page
/// pushed inside a sheet's `NavigationStack`, `dismiss` goes back a page, so
/// pass the sheet's own dismiss as `onClose` and use `onBack` for the back button.
/// `SheetScreen` draws the header above a sheet's content for you.
public struct SheetHeader<Accessory: View>: View {
    @Environment(\.dismiss) private var dismiss
    private let title: String
    private let onBack: (() -> Void)?
    private let backLabel: String
    private let closeLabel: String
    private let onClose: (() -> Void)?
    private let accessory: Accessory
    @State private var titleWidth: CGFloat?

    /// - Parameters:
    ///   - title: The sheet's title, drawn in `Font.screenTitle` like an app's.
    ///   - onBack: Shows a back button before the title, for a page pushed inside the sheet.
    ///   - backLabel: What VoiceOver reads for the back button, usually the previous page's name.
    ///   - closeLabel: What VoiceOver reads for the close button. "Close" by default.
    ///   - onClose: What the close button does. Dismisses the sheet when nil.
    ///   - accessory: The toolbar before the close button: at most one prominent
    ///     action, then any `GlassIconButton`s, `GlassCapsuleButton`s and
    ///     `HeaderMenu`s, without a stack around them. A lone trailing closure
    ///     is the toolbar. It has no default, since a defaulted toolbar would
    ///     leave that closure to `onBack`, which comes first.
    public init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back",
        closeLabel: String = "Close", onClose: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.onBack = onBack
        self.backLabel = backLabel
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.accessory = accessory()
    }

    public var body: some View {
        HeaderRow(split: Accessory.self == EmptyView.self ? .sheetCloseOnly : .sheet, titleWidth: titleWidth) {
            HeaderLeading(title: title) {
                if let onBack {
                    GlassIconButton("chevron.left", label: backLabel, action: onBack)
                }
            } titleAccessory: {
                EmptyView()
            }
        } trailing: {
            HeaderTrailing(items: accessory, close: CloseButton(closeLabel, action: close), showsClock: false)
        }
        .background { titleMeasure }
        .dynamicTypeSize(...ToolbarMetrics.largestTypeSize)
        // Lets UI tests find a sheet's own title and buttons apart from the screen under it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheetHeader")
    }

    /// The leading side at full size, never shown: the back button's room
    /// and the title, as `HeaderLeading` lays them out. It holds no glass and
    /// depends only on the title, so measuring it never moves the sides.
    private var titleMeasure: some View {
        HStack(spacing: Theme.Spacing.s) {
            if onBack != nil {
                Color.clear.frame(width: Theme.Size.toolbarItem, height: 0)
            }
            Text(title)
                .font(.screenTitle)
                .lineLimit(1)
                .padding(.trailing, Theme.Spacing.xs)
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

public extension SheetHeader where Accessory == EmptyView {
    /// A header with only the title and the close button, for a sheet whose
    /// changes apply as they are made.
    init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back",
        closeLabel: String = "Close", onClose: (() -> Void)? = nil
    ) {
        self.init(title, onBack: onBack, backLabel: backLabel, closeLabel: closeLabel, onClose: onClose) { EmptyView() }
    }
}

/// A sheet's chrome: the sheet header (title, toolbar, close button) above
/// the sheet's content. Every sheet and modal form uses it, the way every app
/// uses `AppScreen`.
///
///     SheetScreen("Add Station") {
///         GlassCapsuleButton("Add", isProminent: true, action: add).disabled(url.isEmpty)
///     } content: {
///         Form { ... }
///     }
///
/// The header is padded by `Theme.Spacing.l`, like an app's. The content
/// reaches the sheet's edges, so a `List` or `Form` scrolls edge to edge with
/// its own insets, on the sheet's background. Pad other content yourself, by
/// `Theme.Spacing.l` or more. In Light the sheet is the grouped page color
/// (`Color.groupedBackground`), a light gray, so a form's white rows stand out
/// as in iPadOS. In Dark it keeps the sheet's own dark background.
/// Inside a `NavigationStack` it hides the system bar, so a page pushed in a
/// sheet uses `onBack` for its back button.
public struct SheetScreen<Content: View, Accessory: View>: View {
    private let title: String
    private let onBack: (() -> Void)?
    private let backLabel: String
    private let closeLabel: String
    private let onClose: (() -> Void)?
    private let accessory: Accessory
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - title: The sheet's title.
    ///   - onBack: Shows a back button before the title, for a page pushed inside the sheet.
    ///   - backLabel: What VoiceOver reads for the back button.
    ///   - closeLabel: What VoiceOver reads for the close button.
    ///   - onClose: What the close button does. Dismisses the sheet when nil.
    ///   - accessory: The toolbar before the close button, with the one
    ///     prominent action. The first of two trailing closures.
    ///   - content: The sheet's content, edge to edge under the header.
    public init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back",
        closeLabel: String = "Close", onClose: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onBack = onBack
        self.backLabel = backLabel
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SheetHeader(title, onBack: onBack, backLabel: backLabel, closeLabel: closeLabel, onClose: onClose) {
                accessory
            }
            .padding([.horizontal, .top], Theme.Spacing.l)
            content
                // Lists and forms show the sheet's own background, as the
                // header does, instead of a band of another gray under it.
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background {
            if colorScheme == .light { Color.groupedBackground.ignoresSafeArea() }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

public extension SheetScreen where Accessory == EmptyView {
    /// A sheet with no toolbar, only the title and the close button, for
    /// changes that apply as they are made. A lone trailing closure is the content.
    ///
    ///     SheetScreen("Wallpaper") { WallpaperGrid() }
    init(
        _ title: String, onBack: (() -> Void)? = nil, backLabel: String = "Back",
        closeLabel: String = "Close", onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, onBack: onBack, backLabel: backLabel, closeLabel: closeLabel, onClose: onClose,
                  accessory: { EmptyView() }, content: content)
    }
}
