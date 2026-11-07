import SwiftUI

/// A header row: the leading side in the leading half, the trailing side in
/// the trailing half, and nothing in the `Theme.Size.nowPlayingZone` at the
/// center, where the shell draws the Now Playing pill. Headers span the
/// screen, so the center of the row is the pill's. Each side gets exactly its
/// half (`HeaderMetrics.sideWidth`), so a side that needs more room takes a
/// smaller stage or shrinks instead of reaching the center. A sheet's header
/// splits its row another way (`HeaderSplit.sheet`), since the pill never
/// covers a sheet.
///
/// The row knows its own width and gives each side a frame of fixed width,
/// so the `ViewThatFits` stages inside a side are only ever measured at that
/// one width. On iOS 27 a `ViewThatFits` with glass inside breaks in two
/// ways, and `HeaderLayoutTests` catches both:
/// - Measured at changing widths, as a stack measures a flexible child at no
///   width and at any width, it makes SwiftUI lay the screen out again and
///   again for good. That is the Faces freeze. It came back in a test window
///   with a stack around the toolbar (as before 0805531) and with a stack of
///   two flexible sides.
/// - Measured by a custom `Layout`, as the row's own layout did, it trips an
///   AttributeGraph precondition (`input_value_ref_slow`) when `ImageRenderer`
///   draws the header.
///
/// The width is the size the parent gives the row, which never depends on the
/// sides, so it settles in one update. Until it is known the row is empty.
struct HeaderRow<Leading: View, Trailing: View>: View {
    private let split: HeaderSplit
    private let titleWidth: CGFloat?
    private let leading: Leading
    private let trailing: Trailing
    @State private var width: CGFloat?

    /// - Parameters:
    ///   - split: How the row divides its width. Halves around the Now Playing zone by default.
    ///   - titleWidth: What the leading side needs at full size, for a split that uses it.
    init(split: HeaderSplit = .app, titleWidth: CGFloat? = nil,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.split = split
        self.titleWidth = titleWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            if let width {
                let sides = split.sides(rowWidth: width, titleWidth: titleWidth)
                leading.modifier(HeaderSide(width: sides.leading, alignment: .leading))
                Color.clear
                    .frame(width: split.center, height: 0)
                trailing.modifier(HeaderSide(width: sides.trailing, alignment: .trailing))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// One side of a header row: a fixed width with the content at the side's
/// edge, centered vertically. The content is asked for its size with that
/// width and no height, the same question every time.
private struct HeaderSide: ViewModifier {
    let width: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: alignment)
    }
}

/// The leading side of a header: an optional back button, the title in
/// `Font.screenTitle` and a title accessory, at the first stage that fits its
/// half. Pickers in the accessory show their symbol before the title shrinks
/// to 70 percent and then cuts off. `AppHeader` and `SheetHeader` share it.
struct HeaderLeading<Back: View, TitleAccessory: View>: View {
    private let title: String
    private let back: Back
    private let titleAccessory: TitleAccessory

    init(title: String, @ViewBuilder back: () -> Back, @ViewBuilder titleAccessory: () -> TitleAccessory) {
        self.title = title
        self.back = back()
        self.titleAccessory = titleAccessory()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full, scalesTitle: false)
            row(.compact, scalesTitle: false)
            row(.compact, scalesTitle: true)
        }
    }

    /// The back button, title and title accessory at one stage. The last
    /// candidate lets the title shrink and then cut off.
    private func row(_ stage: ToolbarStage, scalesTitle: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            back
            if !title.isEmpty {
                Text(title)
                    .font(.screenTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(scalesTitle ? 0.7 : 1)
                    .fixedSize(horizontal: !scalesTitle, vertical: false)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.trailing, Theme.Spacing.xs)
            }
            titleAccessory
        }
        .environment(\.toolbarPlacement, .bar(stage))
    }
}

/// The trailing side of a header: its toolbar items, then the close button.
/// The items take the first stage that fits: everything, then symbols for
/// titles, then low priority items in a More menu, then only More and the
/// prominent action. The close button never moves.
///
/// - Each stage is a whole row, close button included, in a glass container
///   of its own. One container around every stage froze the app on iPadOS 27:
///   `ViewThatFits` measures stages it never shows, their glass joined the
///   shown stage's container, and resolving that glass during measurement
///   started the measurement again, for good.
/// - A stage is one stack around the items, not a stack in a stack, so
///   measuring a stage goes no deeper than the items need.
/// - `ViewThatFits` chooses because the stages it only measures never come
///   alive. A view that kept every stage laid out and showed one would run
///   every item four times, such as the AirPlay picker behind the Music
///   speaker button, which would then try to open four times.
struct HeaderTrailing<Items: View>: View {
    let items: Items
    let close: CloseButton?
    /// The time beside the close button, as on HomeView's app screens. Sheets
    /// leave it out.
    var showsClock = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.compact)
            row(.overflow)
            row(.minimal)
        }
    }

    private func row(_ stage: ToolbarStage) -> some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                if stage >= .overflow {
                    moreMenu(stage)
                }
                items
                // The first thing to leave when the toolbar runs short of room.
                if showsClock, stage <= .compact {
                    HeaderClock()
                }
                if let close {
                    // Not a toolbar item: the close button never moves into More.
                    close.environment(\.toolbarPlacement, .standalone)
                }
            }
            .environment(\.toolbarPlacement, .bar(stage))
        }
        .fixedSize()
    }

    /// The items that left the bar at this stage, in a menu at the start of
    /// the toolbar, so the prominent action and the close button stay put.
    private func moreMenu(_ stage: ToolbarStage) -> some View {
        Menu {
            items.environment(\.toolbarPlacement, .menu(stage))
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .buttonStyle(.glassIcon())
        .accessibilityLabel("More")
    }
}
