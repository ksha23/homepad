import HomePadCore
import SwiftUI

/// A Smart Stack the widget gallery offers first, as on iPadOS: a widget
/// stack (`WidgetStack`) that starts with sensible widgets for its size.
public struct SmartStackOffer {
    /// The widgets a new stack of a size starts with, in order. A size with
    /// fewer than two is not offered.
    public let widgets: (WidgetSize) -> [WidgetDescriptor]
    /// Called with the size shown and its widgets when Add Widget is tapped.
    public let onAdd: (WidgetSize, [WidgetDescriptor]) -> Void

    public init(widgets: @escaping (WidgetSize) -> [WidgetDescriptor],
                onAdd: @escaping (WidgetSize, [WidgetDescriptor]) -> Void) {
        self.widgets = widgets
        self.onAdd = onAdd
    }

    /// The sizes it is offered at.
    var sizes: [WidgetSize] {
        WidgetSize.allCases.filter { widgets($0).count >= 2 }
    }
}

/// The iPadOS widget gallery, for any place widgets can be added: every
/// widget as a big live preview, then a page for the one you tap, where you
/// swipe through its sizes and tap Add Widget. With a `SmartStackOffer` the
/// Smart Stack comes first, as on iPadOS.
///
///     WidgetGallery(widgets: registry.widgets, tileSize: { grid.tileSize($0) }, onAdd: add) { widget, size in
///         widget.makeView(size)
///     }
///
/// Present it in a sheet with `.presentationSizing(.page)`, so the previews
/// have room. It has its own navigation, and a sheet header on each page
/// with the close button, and a back button on a widget's page.
public struct WidgetGallery<Preview: View>: View {
    private let widgets: [WidgetDescriptor]
    private let tileSize: (WidgetSize) -> CGSize
    private let unavailableReason: (WidgetDescriptor, WidgetSize) -> String?
    private let openingSize: WidgetSize?
    private let empty: (title: String, message: String)
    private let smartStack: SmartStackOffer?
    private let onAdd: (WidgetDescriptor, WidgetSize) -> Void
    private let preview: (WidgetDescriptor, WidgetSize) -> Preview
    @State private var path: [String]
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    /// The width of a widget's card in the gallery.
    static var cardWidth: CGFloat { 320 }
    /// The height of the preview on a card, so cards line up row by row.
    static var cardPreviewHeight: CGFloat { 210 }
    /// The Smart Stack's ID in the gallery, for `opening` it first.
    public static var smartStackID: String { "homepad.smartStack" }

    /// - Parameters:
    ///   - widgets: The widgets to offer, in order.
    ///   - tileSize: The size each widget size is drawn at where it will sit,
    ///     so previews match it exactly.
    ///   - unavailableReason: Why a widget cannot be added at a size, such as
    ///     no room for it, or nil when it can. Add Widget is off with the reason under it.
    ///   - widgetID: A widget whose page opens first, at `size` when given.
    ///     `smartStackID` opens the Smart Stack's.
    ///   - empty: What the gallery says when it has no widgets to offer.
    ///   - smartStack: A Smart Stack to offer first, or nil for none.
    ///   - onAdd: Called with the widget and the size shown when Add Widget is tapped.
    ///   - preview: Draws a widget at a size, to fill its tile.
    public init(
        widgets: [WidgetDescriptor], tileSize: @escaping (WidgetSize) -> CGSize,
        unavailableReason: @escaping (WidgetDescriptor, WidgetSize) -> String? = { _, _ in nil },
        opening widgetID: String? = nil, size: WidgetSize? = nil,
        empty: (title: String, message: String) = ("No Widgets", "Widgets from other parts of HomePad appear here."),
        smartStack: SmartStackOffer? = nil,
        onAdd: @escaping (WidgetDescriptor, WidgetSize) -> Void,
        @ViewBuilder preview: @escaping (WidgetDescriptor, WidgetSize) -> Preview
    ) {
        self.widgets = widgets
        self.tileSize = tileSize
        self.unavailableReason = unavailableReason
        openingSize = size
        self.empty = empty
        self.smartStack = smartStack
        self.onAdd = onAdd
        self.preview = preview
        _path = State(initialValue: widgetID.map { [$0] } ?? [])
    }

    public var body: some View {
        NavigationStack(path: $path) {
            SheetScreen("Widgets", onClose: { dismiss() }) {
                VStack(spacing: Theme.Spacing.s) {
                    GlassSearchField("Search Widgets", text: $search)
                        .padding(.horizontal, Theme.Spacing.l)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Theme.Spacing.l)],
                                  spacing: Theme.Spacing.xl) {
                            ForEach(matching) { widget in
                                NavigationLink(value: widget.id) {
                                    card(widget)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityLabel(widget.title)
                                .accessibilityHint("Shows its sizes")
                            }
                        }
                        .padding(Theme.Spacing.l)
                    }
                    .overlay {
                        if matching.isEmpty {
                            if search.isEmpty {
                                ContentUnavailableView(empty.title, systemImage: "square.grid.2x2", description: Text(empty.message))
                            } else {
                                ContentUnavailableView.search(text: search)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let widget = offered.first(where: { $0.id == id }) {
                    // `dismiss` here is the gallery's own, so the close button closes the sheet.
                    SheetScreen(widget.title, onBack: { path.removeLast() }, backLabel: "Widgets", onClose: { dismiss() }) {
                        WidgetSizePager(widget: widget, startSize: id == path.first ? openingSize : nil,
                                        tileSize: tileSize, unavailableReason: unavailableReason,
                                        detail: { stackDetail(widget, $0) }, onAdd: add, preview: galleryPreview)
                    }
                }
            }
        }
    }

    /// Everything the gallery lists: the Smart Stack first when it has a size to offer, then the widgets.
    private var offered: [WidgetDescriptor] {
        guard let smartStack, !smartStack.sizes.isEmpty else { return widgets }
        // It stands in for the stack in the gallery's lists and pages. It is never placed.
        let stack = WidgetDescriptor(id: Self.smartStackID, title: "Smart Stack", systemImage: "square.stack.3d.up.fill",
                                     supportedSizes: smartStack.sizes) { _ in EmptyView() }
        return [stack] + widgets
    }

    private var matching: [WidgetDescriptor] {
        guard !search.isEmpty else { return offered }
        return offered.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func add(_ widget: WidgetDescriptor, _ size: WidgetSize) {
        if widget.id == Self.smartStackID, let smartStack {
            smartStack.onAdd(size, smartStack.widgets(size))
        } else {
            onAdd(widget, size)
        }
    }

    /// A widget as the gallery draws it: the caller's preview, or for the
    /// Smart Stack its first widget with the dots that say more are behind it.
    @ViewBuilder
    private func galleryPreview(_ widget: WidgetDescriptor, _ size: WidgetSize) -> some View {
        if widget.id == Self.smartStackID, let members = smartStack?.widgets(size), let first = members.first {
            preview(first, size)
                .overlay(alignment: .trailing) {
                    StackDots(count: members.count, current: 0)
                        .padding(.trailing, Theme.Spacing.xs)
                }
        } else {
            preview(widget, size)
        }
    }

    /// What a Smart Stack of a size starts with: "Up Next, Weather and Now Playing".
    private func stackDetail(_ widget: WidgetDescriptor, _ size: WidgetSize) -> String? {
        guard widget.id == Self.smartStackID, let members = smartStack?.widgets(size) else { return nil }
        return members.map(\.title).formatted(.list(type: .and))
    }

    /// A widget in the gallery: a big live preview at its featured size, its name and its sizes.
    private func card(_ widget: WidgetDescriptor) -> some View {
        let size = Self.featuredSize(widget.supportedSizes)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            WidgetPreview(tile: tileSize(size), fitting: CGSize(width: Self.cardWidth, height: Self.cardPreviewHeight)) {
                galleryPreview(widget, size)
            }
            .frame(maxWidth: .infinity, minHeight: Self.cardPreviewHeight, alignment: .center)
            Label(widget.title, systemImage: widget.systemImage)
                .font(.headline)
                .lineLimit(1)
            Text(stackDetail(widget, size) ?? widget.supportedSizes.map(\.title).formatted(.list(type: .and)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }

    /// The size a card shows: medium, the widget's most typical shape, when it has one.
    static func featuredSize(_ sizes: [WidgetSize]) -> WidgetSize {
        sizes.contains(.medium) ? .medium : sizes.first ?? .small
    }
}

/// One widget's page in the gallery: a big live preview of each size it
/// supports, swiped through like iPadOS, and Add Widget for the size shown.
struct WidgetSizePager<Preview: View>: View {
    let widget: WidgetDescriptor
    let tileSize: (WidgetSize) -> CGSize
    let unavailableReason: (WidgetDescriptor, WidgetSize) -> String?
    /// A line under the size's name, such as the widgets a Smart Stack starts with.
    let detail: (WidgetSize) -> String?
    let onAdd: (WidgetDescriptor, WidgetSize) -> Void
    let preview: (WidgetDescriptor, WidgetSize) -> Preview
    @State private var size: WidgetSize?

    init(widget: WidgetDescriptor, startSize: WidgetSize?, tileSize: @escaping (WidgetSize) -> CGSize,
         unavailableReason: @escaping (WidgetDescriptor, WidgetSize) -> String?,
         detail: @escaping (WidgetSize) -> String? = { _ in nil },
         onAdd: @escaping (WidgetDescriptor, WidgetSize) -> Void,
         preview: @escaping (WidgetDescriptor, WidgetSize) -> Preview) {
        self.widget = widget
        self.tileSize = tileSize
        self.unavailableReason = unavailableReason
        self.detail = detail
        self.onAdd = onAdd
        self.preview = preview
        let sizes = widget.supportedSizes
        _size = State(initialValue: startSize.flatMap { sizes.contains($0) ? $0 : nil } ?? sizes.first)
    }

    var body: some View {
        let sizes = widget.supportedSizes
        let current = size ?? sizes.first ?? .small
        let reason = unavailableReason(widget, current)
        VStack(spacing: Theme.Spacing.l) {
            Text(sizes.count > 1 ? "Swipe to choose a size." : "This widget has one size.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(sizes, id: \.self) { size in
                            WidgetPreview(tile: tileSize(size),
                                          fitting: CGSize(width: proxy.size.width * 0.86, height: proxy.size.height)) {
                                preview(widget, size)
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(widget.title), \(size.title)")
                            .id(size)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $size)
                .scrollIndicators(.hidden)
            }
            VStack(spacing: Theme.Spacing.s) {
                Text(current.title)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                if let line = detail(current) {
                    Text(line)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
                PageDots(count: sizes.count, selection: Binding(
                    get: { sizes.firstIndex(of: current) ?? 0 },
                    set: { index in withAnimation(Theme.Motion.standard) { size = sizes[index] } }
                ))
            }
            GlassCapsuleButton("Add Widget", systemImage: "plus", isProminent: true) { onAdd(widget, current) }
                .disabled(reason != nil)
            // The line is always there, so the button does not move as sizes change.
            Text(reason ?? " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding([.horizontal, .bottom], Theme.Spacing.xl)
        .animation(Theme.Motion.standard, value: current)
        .sensoryFeedback(.selection, trigger: current)
    }

}
